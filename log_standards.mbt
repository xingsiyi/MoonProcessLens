///|
fn date_digits(
  text : String,
  offset : Int32,
  length : Int32,
) -> Int32 raise ProcessError {
  model_require(
    offset >= 0 && offset + length <= text.length(),
    "timestamp",
    "truncated date",
  )
  let mut value = 0
  for i in offset..<(offset + length) {
    let digit = text.code_unit_at(i).to_int() - 48
    model_require(digit >= 0 && digit <= 9, "timestamp", "expected date digits")
    value = value * 10 + digit
  }
  value
}

///|
fn leap_year(year : Int32) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn days_before(year : Int32) -> Int64 {
  let y = (year - 1).to_int64()
  365L * y + y / 4L - y / 100L + y / 400L
}

///|
fn month_days(year : Int32) -> Array[Int32] {
  [
    31,
    if leap_year(year) {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
}

///|
/// ISO8601 profile: Gregorian 1970..9999, mandatory Z or ±hh:mm, optional
/// 1..9 fractional digits only when exactly representable in milliseconds.
/// No leap seconds, floating local time or rounding.
fn parse_xes_time(text : String) -> Int64 raise ProcessError {
  model_require(
    text.length() >= 20 && text.length() <= 35,
    "timestamp",
    "expected ISO8601 millisecond timestamp with zone",
  )
  model_require(
    text[4:5] == "-" &&
    text[7:8] == "-" &&
    text[10:11] == "T" &&
    text[13:14] == ":" &&
    text[16:17] == ":",
    "timestamp",
    "invalid ISO8601 separators",
  )
  let year = date_digits(text, 0, 4)
  let month = date_digits(text, 5, 2)
  let day = date_digits(text, 8, 2)
  let hour = date_digits(text, 11, 2)
  let minute = date_digits(text, 14, 2)
  let second = date_digits(text, 17, 2)
  model_require(
    year >= 1970 &&
    year <= 9999 &&
    month >= 1 &&
    month <= 12 &&
    hour <= 23 &&
    minute <= 59 &&
    second <= 59,
    "timestamp",
    "date/time out of range",
  )
  let months = month_days(year)
  model_require(
    day >= 1 && day <= months[month - 1],
    "timestamp",
    "invalid calendar day",
  )
  let mut offset = 19
  let mut millis = 0
  if text[offset:offset + 1] == "." {
    offset += 1
    let start = offset
    while offset < text.length() &&
          text.code_unit_at(offset).to_int() >= 48 &&
          text.code_unit_at(offset).to_int() <= 57 {
      offset += 1
    }
    let count = offset - start
    model_require(
      count >= 1 && count <= 9,
      "timestamp",
      "invalid fractional seconds",
    )
    if count > 3 {
      for i in (start + 3)..<offset {
        model_require(
          text.code_unit_at(i).to_int() == 48,
          "timestamp",
          "nonzero submillisecond precision unsupported",
        )
      }
    }
    let width = count.min(3)
    millis = date_digits(text, start, width) *
      (if width == 1 { 100 } else if width == 2 { 10 } else { 1 })
  }
  let mut zone = 0
  if text[offset:] == "Z" {
    offset += 1
  } else {
    model_require(
      text.length() - offset == 6 &&
      (text[offset:offset + 1] == "+" || text[offset:offset + 1] == "-") &&
      text[offset + 3:offset + 4] == ":",
      "timestamp",
      "mandatory timezone",
    )
    let h = date_digits(text, offset + 1, 2)
    let m = date_digits(text, offset + 4, 2)
    model_require(
      h <= 14 && m <= 59 && (h != 14 || m == 0),
      "timestamp",
      "timezone out of range",
    )
    zone = (h * 60 + m) * (if text[offset:offset + 1] == "+" { 1 } else { -1 })
    offset += 6
  }
  model_require(offset == text.length(), "timestamp", "trailing date data")
  let mut days = days_before(year) - days_before(1970) + (day - 1).to_int64()
  for i in 0..<(month - 1) {
    days += months[i].to_int64()
  }
  let result = (
      (days * 24L + hour.to_int64()) * 3600L +
      minute.to_int64() * 60L +
      second.to_int64() -
      zone.to_int64() * 60L
    ) *
    1000L +
    millis.to_int64()
  model_require(
    result >= 0L && result <= 253402300799999L,
    "timestamp",
    "UTC instant must lie within 1970..9999",
  )
  result
}

///|
fn pad_date(value : Int32, width : Int32) -> String {
  let out = StringBuilder()
  let digits = value.to_string()
  for _ in digits.length()..<width {
    out.write_string("0")
  }
  out.write_string(digits)
  out.to_string()
}

///|
fn xes_time(timestamp : Int64) -> String raise ProcessError {
  model_require(
    timestamp >= 0L && timestamp <= 253402300799999L,
    "timestamp",
    "XES export supports year 1970..9999",
  )
  let days = timestamp / 86400000L
  let mut low = 1970
  let mut high = 10000
  while low + 1 < high {
    let middle = (low + high) / 2
    if days_before(middle) - days_before(1970) <= days {
      low = middle
    } else {
      high = middle
    }
  }
  let mut remaining = (days - (days_before(low) - days_before(1970))).to_int()
  let mut month = 1
  let months = month_days(low)
  while remaining >= months[month - 1] {
    remaining -= months[month - 1]
    month += 1
  }
  "\{pad_date(low,4)}-\{pad_date(month,2)}-\{pad_date(remaining+1,2)}T\{pad_date(((timestamp/3600000L)%24L).to_int(),2)}:\{pad_date(((timestamp/60000L)%60L).to_int(),2)}:\{pad_date(((timestamp/1000L)%60L).to_int(),2)}.\{pad_date((timestamp%1000L).to_int(),3)}Z"
}

///|
pub(all) enum XesMode {
  Completed
  LifecyclePairs
}

///|
priv struct XesOccurrence {
  activity : String
  stamp : Int64
  lifecycle : String
  resource : String?
  id : String?
  instance : String?
}

///|
fn xes_attributes(node : ModelXml) -> Map[String, String] raise ProcessError {
  let result : Map[String, String] = Map([])
  for child in node.children {
    if child.ns != node.ns {
      raise InvalidLog(path="xes.namespace", reason="foreign attribute element")
    }
    model_require(
      child.text.trim().is_empty(),
      "xes.attribute",
      "non-whitespace mixed text unsupported",
    )
    if ["string", "date", "int", "float", "boolean", "id"].contains(child.name) {
      model_require(
        child.children.is_empty(),
        "xes.attribute",
        "nested/list attributes unsupported",
      )
      let key = child.attribute("key")
      model_require(
        !result.contains(key),
        "xes.attribute",
        "duplicate attribute key",
      )
      let value = child.attribute("value")
      if [
          "concept:name", "org:resource", "lifecycle:transition", "concept:instance",
          "lens:event_id",
        ].contains(key) {
        model_require(
          child.name == "string",
          "xes.attribute",
          "expected string attribute",
        )
      }
      if key == "time:timestamp" || key == "lens:started" {
        model_require(
          child.name == "date",
          "xes.attribute",
          "expected date attribute",
        )
      }
      result[key] = value
    } else if child.name != "event" || node.name != "trace" {
      raise InvalidLog(
        path="xes.attribute",
        reason="unsupported XES attribute type",
      )
    }
  }
  result
}

///|
fn xes_with_defaults(
  node : ModelXml,
  defaults : Map[String, String],
) -> Map[String, String] raise ProcessError {
  let values = defaults.copy()
  for key, value in xes_attributes(node) {
    values[key] = value
  }
  values
}

///|
fn xes_required(
  values : Map[String, String],
  key : String,
) -> String raise ProcessError {
  values
  .get(key)
  .unwrap_or_else(() => raise InvalidLog(path="xes", reason="missing \{key}"))
}

///|
/// XES XML scalar-attribute profile. Completed mode maps completion events to
/// points unless lens:started is supplied. Pairing mode requires start/complete
/// with matching (activity, concept:instance); ambiguous overlaps are rejected.
pub fn parse_xes(
  text : String,
  mode~ : XesMode = Completed,
) -> EventLog raise ProcessError {
  let root = model_xml(text)
  model_require(
    root.name == "log" && ["", "http://www.xes-standard.org/"].contains(root.ns),
    "xes",
    "expected XES log namespace",
  )
  model_require(
    root.text.trim().is_empty(),
    "xes",
    "mixed log text unsupported",
  )
  let events : Array[LogEvent] = []
  let cases : Map[String, Bool] = Map([])
  let trace_defaults : Map[String, String] = Map([])
  let event_defaults : Map[String, String] = Map([])
  let scopes : Map[String, Bool] = Map([])
  for child in root.children {
    if child.name == "global" {
      model_require(child.ns == root.ns, "xes.namespace", "mixed namespace")
      model_require(
        child.text.trim().is_empty(),
        "xes.global",
        "mixed text unsupported",
      )
      let scope = child.attribute("scope")
      model_require(
        ["trace", "event"].contains(scope),
        "xes.global",
        "invalid scope",
      )
      model_require(!scopes.contains(scope), "xes.global", "duplicate scope")
      scopes[scope] = true
      let defaults = if scope == "trace" {
        trace_defaults
      } else {
        event_defaults
      }
      for key, value in xes_attributes(child) {
        defaults[key] = value
      }
    }
  }
  for trace_index, trace in root.children {
    model_require(trace.ns == root.ns, "xes.namespace", "mixed namespace")
    if trace.name != "trace" {
      model_require(
        [
          "extension", "classifier", "string", "date", "int", "float", "boolean",
          "id", "global",
        ].contains(trace.name),
        "xes.log",
        "unsupported log child",
      )
      continue
    }
    let values = xes_with_defaults(trace, trace_defaults)
    model_require(
      trace.text.trim().is_empty(),
      "xes.trace",
      "mixed trace text unsupported",
    )
    let case_id = xes_required(values, "concept:name")
    model_require(!cases.contains(case_id), "xes.trace", "duplicate case ID")
    cases[case_id] = true
    if cases.length() > 10000 {
      raise Capacity(resource="XES cases", limit=10000)
    }
    let pending : Map[String, XesOccurrence] = Map([])
    let mut event_count = 0
    for event_index, event in trace.children {
      if event.name != "event" {
        continue
      }
      event_count += 1
      let values = xes_with_defaults(event, event_defaults)
      let occurrence : XesOccurrence = {
        activity: xes_required(values, "concept:name"),
        stamp: parse_xes_time(xes_required(values, "time:timestamp")),
        lifecycle: values.get("lifecycle:transition").unwrap_or("complete"),
        resource: values.get("org:resource"),
        id: values.get("lens:event_id"),
        instance: values.get("concept:instance"),
      }
      let id = occurrence.id.unwrap_or("xes-\{trace_index}-\{event_index}")
      let key = path_identity([
        occurrence.activity,
        occurrence.instance.unwrap_or(""),
      ])
      match mode {
        Completed => {
          model_require(
            occurrence.lifecycle == "complete",
            "xes.lifecycle",
            "completed profile requires completion events",
          )
          let started = match values.get("lens:started") {
            Some(v) => parse_xes_time(v)
            None => occurrence.stamp
          }
          events.push(
            LogEvent::new(
              id,
              case_id,
              occurrence.activity,
              started,
              occurrence.stamp,
              resource=occurrence.resource,
            ),
          )
        }
        LifecyclePairs => {
          model_require(
            !values.contains("lens:started"),
            "xes.lifecycle",
            "interval extension and pairing cannot be mixed",
          )
          if occurrence.lifecycle == "start" {
            model_require(
              !pending.contains(key),
              "xes.lifecycle",
              "ambiguous overlapping activity; supply distinct concept:instance",
            )
            pending[key] = occurrence
          } else {
            model_require(
              occurrence.lifecycle == "complete",
              "xes.lifecycle",
              "only start/complete supported",
            )
            let start = pending
              .get(key)
              .unwrap_or_else(() => {
                raise InvalidLog(
                  path="xes.lifecycle",
                  reason="unmatched completion",
                )
              })
            model_require(
              start.resource is None ||
              occurrence.resource is None ||
              start.resource == occurrence.resource,
              "xes.resource",
              "resource changed within activity",
            )
            events.push(
              LogEvent::new(
                id,
                case_id,
                occurrence.activity,
                start.stamp,
                occurrence.stamp,
                resource=match occurrence.resource {
                  Some(v) => Some(v)
                  None => start.resource
                },
              ),
            )
            pending.remove(key) |> ignore
          }
        }
      }
      if events.length() > 100000 {
        raise Capacity(resource="XES events", limit=100000)
      }
    }
    model_require(
      event_count > 0,
      "xes.trace",
      "empty traces cannot be represented by interval EventLog",
    )
    model_require(pending.is_empty(), "xes.lifecycle", "unmatched start")
  }
  EventLog::new(events)
}

///|
/// Non-lossless projection: exports core event fields only. Time unit must be
/// Unix milliseconds. Completion is standard; lens:started preserves intervals.
pub fn EventLog::to_xes(self : EventLog) -> String raise ProcessError {
  let out = StringBuilder()
  out.write_string(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><log xmlns=\"http://www.xes-standard.org/\" xes.version=\"1.0\" xes.features=\"\">",
  )
  for trace in self.traces {
    out.write_string(
      "<trace><string key=\"concept:name\" value=\"\{xml_escape(trace.id)}\"/>",
    )
    for event in trace.events {
      out.write_string(
        "<event><string key=\"concept:name\" value=\"\{xml_escape(event.activity)}\"/><string key=\"lens:event_id\" value=\"\{xml_escape(event.id)}\"/><string key=\"lifecycle:transition\" value=\"complete\"/><date key=\"time:timestamp\" value=\"\{xes_time(event.completed)}\"/><date key=\"lens:started\" value=\"\{xes_time(event.started)}\"/>",
      )
      if event.resource is Some(value) {
        out.write_string(
          "<string key=\"org:resource\" value=\"\{xml_escape(value)}\"/>",
        )
      }
      out.write_string("</event>")
    }
    out.write_string("</trace>")
  }
  out.write_string("</log>")
  let result = out.to_string()
  if result.length() > 16777216 {
    raise Capacity(resource="XES output units", limit=16777216)
  }
  result
}
