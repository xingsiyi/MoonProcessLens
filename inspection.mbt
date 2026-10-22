///|
pub(all) struct PartitionStatus {
  key : String
  buffered : Int32
  active : Int32
  earliest_event : Int64?
  latest_event : Int64?
  earliest_deadline : Int64?
}

///|
pub(all) struct PatternStatus {
  pattern : String
  active : Int32
  awaiting_absence : Int32
  earliest_deadline : Int64?
}

///|
pub struct Inspection {
  watermark : Int64
  occurrence : Int64
  buffered : Int32
  active : Int32
  partitions : Array[PartitionStatus]
  patterns : Array[PatternStatus]
}

///|
fn min_optional(current : Int64?, candidate : Int64) -> Int64? {
  Some(
    match current {
      Some(value) => value.min(candidate)
      None => candidate
    },
  )
}

///|
fn max_optional(current : Int64?, candidate : Int64) -> Int64? {
  Some(
    match current {
      Some(value) => value.max(candidate)
      None => candidate
    },
  )
}

///|
fn empty_partition(key : String) -> PartitionStatus {
  {
    key,
    buffered: 0,
    active: 0,
    earliest_event: None,
    latest_event: None,
    earliest_deadline: None,
  }
}

///|
/// Snapshot current committed occupancy without including business field values.
pub fn Engine::inspect(self : Engine) -> Inspection {
  let partitions : Map[String, PartitionStatus] = Map([])
  let patterns : Array[PatternStatus] = self.patterns.map(pattern => {
    pattern: pattern.id,
    active: 0,
    awaiting_absence: 0,
    earliest_deadline: None,
  })
  for item in self.buffer {
    let old = partitions
      .get(item.event.key)
      .unwrap_or(empty_partition(item.event.key))
    partitions.set(item.event.key, {
      ..old,
      buffered: old.buffered + 1,
      earliest_event: min_optional(old.earliest_event, item.event.time),
      latest_event: max_optional(old.latest_event, item.event.time),
    })
  }
  for branch in self.active {
    let pattern = self.patterns[branch.pattern_index]
    let deadline = branch.started + pattern.within
    let old = partitions.get(branch.key).unwrap_or(empty_partition(branch.key))
    partitions.set(branch.key, {
      ..old,
      active: old.active + 1,
      earliest_deadline: min_optional(old.earliest_deadline, deadline),
    })
    let rule = patterns[branch.pattern_index]
    patterns[branch.pattern_index] = {
      ..rule,
      active: rule.active + 1,
      awaiting_absence: rule.awaiting_absence +
      (if branch.stage == pattern.stages.length() { 1 } else { 0 }),
      earliest_deadline: min_optional(rule.earliest_deadline, deadline),
    }
  }
  let rows = partitions.values().collect()
  rows.sort_by((a, b) => a.key.compare(b.key))
  {
    watermark: self.watermark,
    occurrence: self.ordinal,
    buffered: self.buffer.length(),
    active: self.active.length(),
    partitions: rows,
    patterns,
  }
}

///|
/// Earliest buffered event, for host-driven watermark and batching policies.
pub fn Engine::next_event_time(self : Engine) -> Int64? {
  if self.buffer.is_empty() {
    None
  } else {
    Some(self.buffer[0].event.time)
  }
}

///|
/// Earliest active deadline. The host still determines when event time is
/// complete; this value must not be treated as a wall-clock watermark.
pub fn Engine::next_deadline(self : Engine) -> Int64? {
  let mut result : Int64? = None
  for branch in self.active {
    result = min_optional(
      result,
      branch.started + self.patterns[branch.pattern_index].within,
    )
  }
  result
}

///|
pub fn Engine::is_finished(self : Engine) -> Bool {
  self.watermark == FINAL_WATERMARK
}

///|
pub fn Inspection::watermark(self : Inspection) -> Int64 {
  self.watermark
}

///|
pub fn Inspection::occurrence(self : Inspection) -> Int64 {
  self.occurrence
}

///|
pub fn Inspection::buffered(self : Inspection) -> Int32 {
  self.buffered
}

///|
pub fn Inspection::active_states(self : Inspection) -> Int32 {
  self.active
}

///|
pub fn Inspection::partitions(self : Inspection) -> Array[PartitionStatus] {
  self.partitions.copy()
}

///|
pub fn Inspection::patterns(self : Inspection) -> Array[PatternStatus] {
  self.patterns.copy()
}

///|
pub(all) struct Pending {
  pattern : String
  key : String
  stage : String?
  matched_here : Int32
  minimum_more : Int32
  maximum_more : Int32
  deadline : Int64
  awaiting_absence : Bool
  captures : Array[Capture]
}

///|
pub struct Frontier {
  items : Array[Pending]
  total : Int32
}

///|
pub fn Frontier::items(self : Frontier) -> Array[Pending] {
  self.items.map(item => { ..item, captures: detach_captures(item.captures), })
}

///|
pub fn Frontier::total(self : Frontier) -> Int32 {
  self.total
}

///|
pub fn Frontier::truncated(self : Frontier) -> Bool {
  self.total > self.items.length()
}

///|
/// Return a bounded diagnostic sample. Truncation never changes recognition.
pub fn Engine::frontier(
  self : Engine,
  key? : String,
  limit~ : Int32 = 128,
) -> Frontier raise CepError {
  if limit < 1 || limit > 10000 {
    raise Invalid(path="frontier.limit", reason="expected 1..10000")
  }
  let items : Array[Pending] = []
  let mut total = 0
  for branch in self.active {
    if key is Some(selected) && branch.key != selected {
      continue
    }
    total += 1
    if items.length() >= limit {
      continue
    }
    let pattern = self.patterns[branch.pattern_index]
    let terminal = branch.stage == pattern.stages.length()
    let stage = if terminal { None } else { Some(pattern.stages[branch.stage]) }
    items.push({
      pattern: pattern.id,
      key: branch.key,
      stage: stage.map(stage => stage.name),
      matched_here: branch.count,
      minimum_more: stage
      .map(stage => (stage.min - branch.count).max(0))
      .unwrap_or(0),
      maximum_more: stage.map(stage => stage.max - branch.count).unwrap_or(0),
      deadline: branch.started + pattern.within,
      awaiting_absence: terminal,
      captures: detach_captures(branch.captures),
    })
  }
  { items, total, }
}

///|
fn optional_time_json(time : Int64?) -> Json {
  match time {
    Some(time) => Json::string(time.to_string())
    None => Json::null()
  }
}

///|
pub fn inspection_to_json(value : Inspection) -> Json {
  {
    "watermark": Json::string(value.watermark.to_string()),
    "occurrence": Json::string(value.occurrence.to_string()),
    "buffered": Json::number(value.buffered.to_double()),
    "active_states": Json::number(value.active.to_double()),
    "partitions": Json::array(
      value.partitions.map(row => {
        "key": Json::string(row.key),
        "buffered": Json::number(row.buffered.to_double()),
        "active": Json::number(row.active.to_double()),
        "earliest_event": optional_time_json(row.earliest_event),
        "latest_event": optional_time_json(row.latest_event),
        "earliest_deadline": optional_time_json(row.earliest_deadline),
      }),
    ),
    "patterns": Json::array(
      value.patterns.map(row => {
        "pattern": Json::string(row.pattern),
        "active": Json::number(row.active.to_double()),
        "awaiting_absence": Json::number(row.awaiting_absence.to_double()),
        "earliest_deadline": optional_time_json(row.earliest_deadline),
      }),
    ),
  }
}
