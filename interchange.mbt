///|
fn parse_process_json(text : String) -> Json raise ProcessError {
  if text.length() > 16777216 {
    raise Capacity(resource="JSON UTF-16 units", limit=16777216)
  }
  @json.parse(text[:], max_nesting_depth=8, reject_duplicate_keys=true) catch {
    error => raise InvalidLog(path="json", reason=error.to_string())
  }
}

///|
fn process_object(
  value : Json,
  allowed : Array[String],
  path : String,
) -> Map[String, Json] raise ProcessError {
  let object = match value {
    Object(object) => object
    _ => raise InvalidLog(path~, reason="expected object")
  }
  for key, _ in object {
    if !allowed.contains(key) {
      raise InvalidLog(path~, reason="unknown property: \{key}")
    }
  }
  object
}

///|
fn process_required(
  object : Map[String, Json],
  key : String,
) -> Json raise ProcessError {
  match object.get(key) {
    Some(value) => value
    None => raise InvalidLog(path=key, reason="missing property")
  }
}

///|
fn process_string(value : Json, path : String) -> String raise ProcessError {
  match value {
    String(value) => value
    _ => raise InvalidLog(path~, reason="expected string")
  }
}

///|
fn process_array(value : Json, path : String) -> Array[Json] raise ProcessError {
  match value {
    Array(value) => value
    _ => raise InvalidLog(path~, reason="expected array")
  }
}

///|
fn process_timestamp(value : Json, path : String) -> Int64 raise ProcessError {
  let text = process_string(value, path)
  if text.is_empty() ||
    text.length() > 16 ||
    (text.length() > 1 && text.has_prefix("0")) {
    raise InvalidLog(
      path~,
      reason="expected canonical nonnegative decimal timestamp string",
    )
  }
  let mut result = 0L
  for ch in text {
    let digit = ch.to_int() - 48
    if digit < 0 || digit > 9 {
      raise InvalidLog(path~, reason="expected decimal digits")
    }
    // At most 16 digits, so every intermediate is well inside Int64.
    result = result * 10L + digit.to_int64()
  }
  if result > 9007199254740991L {
    raise InvalidLog(path~, reason="timestamp exceeds exact range")
  }
  result
}

///|
fn require_log_version(object : Map[String, Json]) -> Unit raise ProcessError {
  match process_required(object, "schema_version") {
    Number(version, ..) if version == 1.0 => ()
    _ => raise InvalidLog(path="schema_version", reason="expected version 1")
  }
}

///|
pub fn parse_log(text : String) -> EventLog raise ProcessError {
  let root = process_object(
    parse_process_json(text),
    ["schema_version", "events"],
    "log",
  )
  require_log_version(root)
  let raw = process_array(process_required(root, "events"), "events")
  if raw.length() > 100000 {
    raise Capacity(resource="log events", limit=100000)
  }
  let events : Array[LogEvent] = []
  for item in raw {
    let row = process_object(
      item,
      ["id", "case_id", "activity", "started", "completed", "resource"],
      "event",
    )
    let resource = match row.get("resource") {
      None | Some(Null) => None
      Some(value) => Some(process_string(value, "resource"))
    }
    events.push(
      LogEvent::new(
        process_string(process_required(row, "id"), "id"),
        process_string(process_required(row, "case_id"), "case_id"),
        process_string(process_required(row, "activity"), "activity"),
        process_timestamp(process_required(row, "started"), "started"),
        process_timestamp(process_required(row, "completed"), "completed"),
        resource~,
      ),
    )
  }
  EventLog::new(events)
}

///|
pub fn log_to_json(log : EventLog) -> Json {
  let events : Array[Json] = []
  for trace in log.traces {
    for event in trace.events {
      events.push({
        "id": Json::string(event.id),
        "case_id": Json::string(event.case_id),
        "activity": Json::string(event.activity),
        "started": Json::string(event.started.to_string()),
        "completed": Json::string(event.completed.to_string()),
        "resource": match event.resource {
          Some(value) => Json::string(value)
          None => Json::null()
        },
      })
    }
  }
  { "schema_version": Json::number(1.0), "events": Json::array(events) }
}

///|
pub struct AlignmentSpec {
  priv paths : Array[ReferencePath]
  priv costs : AlignmentCosts
}

///|
pub fn AlignmentSpec::paths(self : AlignmentSpec) -> Array[ReferencePath] {
  self.paths.map(path => { ..path, activities: path.activities.copy(), })
}

///|
pub fn AlignmentSpec::costs(self : AlignmentSpec) -> AlignmentCosts {
  self.costs
}

///|
fn parse_alignment_cost(
  value : Json,
  path : String,
) -> Int32 raise ProcessError {
  match value {
    Number(value, ..) if value >= 1.0 &&
      value <= 1000.0 &&
      value == value.to_int().to_double() => value.to_int()
    _ => raise InvalidLog(path~, reason="expected integer 1..1000")
  }
}

///|
pub fn parse_alignment_spec(text : String) -> AlignmentSpec raise ProcessError {
  let root = process_object(
    parse_process_json(text),
    ["schema_version", "paths", "costs"],
    "alignment",
  )
  require_log_version(root)
  let raw = process_array(process_required(root, "paths"), "paths")
  if raw.is_empty() || raw.length() > 128 {
    raise InvalidLog(path="paths", reason="expected 1..128 references")
  }
  let paths : Array[ReferencePath] = []
  let names : Map[String, Bool] = Map([])
  for item in raw {
    let row = process_object(item, ["name", "activities"], "path")
    let name = process_string(process_required(row, "name"), "path.name")
    if names.contains(name) {
      raise InvalidLog(path="path.name", reason="duplicate reference name")
    }
    names.set(name, true)
    let activities = process_array(
      process_required(row, "activities"),
      "path.activities",
    )
    if activities.length() > 4096 {
      raise Capacity(resource="reference activities", limit=4096)
    }
    let labels = activities.map(value => process_string(value, "path.activity"))
    paths.push(ReferencePath::new(name, labels))
  }
  let costs = match root.get("costs") {
    None => AlignmentCosts::new()
    Some(value) => {
      let row = process_object(value, ["unexpected", "missing"], "costs")
      AlignmentCosts::new(
        unexpected=parse_alignment_cost(
          process_required(row, "unexpected"),
          "unexpected",
        ),
        missing=parse_alignment_cost(
          process_required(row, "missing"),
          "missing",
        ),
      )
    }
  }
  { paths, costs, }
}
