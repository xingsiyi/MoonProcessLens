///|
struct Branch {
  pattern_index : Int
  key : String
  stage : Int
  count : Int
  captures : Array[Capture]
  positions : Array[Int64]
  started : Int64
  last : Int64
}

///|
pub struct Engine {
  patterns : Array[Pattern]
  limits : Limits
  mut buffer : Array[Stamped]
  mut active : Array[Branch]
  mut watermark : Int64
  mut ordinal : Int64
}

///|
pub fn Engine::new(
  patterns : Array[Pattern],
  limits~ : Limits = Limits::default(),
) -> Engine raise CepError {
  limits.validate()
  if patterns.is_empty() || patterns.length() > 64 {
    raise Invalid(path="patterns", reason="expected 1..64 patterns")
  }
  let names : Map[String, Bool] = Map([])
  for pattern in patterns {
    if names.contains(pattern.id) {
      raise Invalid(path="patterns", reason="duplicate pattern id \{pattern.id}")
    }
    names.set(pattern.id, true)
  }
  {
    patterns: patterns.map(clone_pattern),
    limits,
    buffer: [],
    active: [],
    watermark: -1L,
    ordinal: 0L,
  }
}

///|
pub fn Engine::push(self : Engine, event : Event) -> Int64 raise CepError {
  if event.time <= self.watermark {
    raise LateEvent(time=event.time, watermark=self.watermark)
  }
  if self.buffer.length() >= self.limits.buffered_events {
    raise Resource(resource="buffered events", limit=self.limits.buffered_events)
  }
  if self.ordinal >= 9007199254740991L {
    raise Invalid(path="engine", reason="occurrence sequence exhausted")
  }
  let next = self.ordinal + 1L
  heap_push(self.buffer, { event, ordinal: next })
  self.ordinal = next
  next
}

///|
pub fn Engine::watermark(self : Engine) -> Int64 {
  self.watermark
}

///|
pub fn Engine::buffered(self : Engine) -> Int {
  self.buffer.length()
}

///|
pub fn Engine::active_states(self : Engine) -> Int {
  self.active.length()
}

///|
pub fn Engine::limits(self : Engine) -> Limits {
  self.limits
}

///|
fn branch_signature(branch : Branch) -> String {
  let builder = StringBuilder()
  builder.write_string("\{branch.pattern_index}:\{branch.stage}:\{branch.count}:")
  for capture in branch.captures {
    builder.write_string("\{capture.events.length()},")
  }
  builder.write_string(":")
  for position in branch.positions {
    builder.write_string("\{position},")
  }
  builder.to_string()
}

///|
fn make_match(pattern : Pattern, branch : Branch, absence : Bool) -> Match {
  {
    pattern: pattern.id,
    key: branch.key,
    captures: branch.captures,
    occurrences: branch.positions,
    started: branch.started,
    ended: if absence { branch.started + pattern.within } else { branch.last },
    absence,
  }
}

///|
fn append_state(
  states : Array[Branch],
  branch : Branch,
  seen : Map[String, Bool],
  limits : Limits,
) -> Unit raise CepError {
  let signature = branch_signature(branch)
  if !seen.contains(signature) {
    if states.length() >= limits.active_states {
      raise Resource(resource="active states", limit=limits.active_states)
    }
    seen.set(signature, true)
    states.push(branch)
  }
}

///|
fn append_match(
  matches : Array[Match],
  value : Match,
  limits : Limits,
) -> Unit raise CepError {
  if matches.length() >= limits.outputs_per_call {
    raise Resource(resource="outputs per call", limit=limits.outputs_per_call)
  }
  matches.push(value)
}

///|
fn append_candidate(
  candidates : Array[Match],
  value : Match,
  limits : Limits,
) -> Unit raise CepError {
  if candidates.length() >= limits.active_states {
    raise Resource(resource="match candidates", limit=limits.active_states)
  }
  candidates.push(value)
}

///|
fn expand_branch(
  branch : Branch,
  pattern : Pattern,
  states : Array[Branch],
  matches : Array[Match],
  seen : Map[String, Bool],
  limits : Limits,
  work : Work,
) -> Unit raise CepError {
  work.charge()
  if branch.stage == pattern.stages.length() {
    if pattern.absence is Some(_) {
      append_state(states, branch, seen, limits)
    } else {
      append_candidate(matches, make_match(pattern, branch, false), limits)
    }
    return
  }
  let stage = pattern.stages[branch.stage]
  if branch.count < stage.max {
    append_state(states, branch, seen, limits)
  }
  if branch.count >= stage.min {
    expand_branch(
      { ..branch, stage: branch.stage + 1, count: 0 },
      pattern, states, matches, seen, limits, work,
    )
  }
}

///|
fn consume_branch(
  branch : Branch,
  item : Stamped,
  pattern : Pattern,
  states : Array[Branch],
  matches : Array[Match],
  seen : Map[String, Bool],
  limits : Limits,
  work : Work,
) -> Unit raise CepError {
  work.charge()
  if branch.stage == pattern.stages.length() {
    if pattern.absence is Some(condition) &&
      !condition.evaluate(item.event, branch.captures) {
      append_state(states, branch, seen, limits)
    }
    return
  }
  let stage = pattern.stages[branch.stage]
  if stage.forbidden is Some(condition) &&
    condition.evaluate(item.event, branch.captures) {
    return
  }
  let accepted = stage.condition.evaluate(item.event, branch.captures)
  if stage.contiguity == SkipAny ||
    (stage.contiguity == SkipNext && !accepted) {
    append_state(states, branch, seen, limits)
  }
  if accepted && branch.count < stage.max {
    let captures = detach_captures(branch.captures)
    captures[branch.stage].events.push(item.event)
    let positions = branch.positions.copy()
    positions.push(item.ordinal)
    expand_branch(
      { ..branch, count: branch.count + 1, captures, positions, last: item.event.time },
      pattern, states, matches, seen, limits, work,
    )
  }
}

///|
fn first_position(branch : Branch) -> Int64 {
  branch.positions[0]
}

///|
fn start_skipped(
  started : Int64,
  first : Int64,
  key : String,
  pattern : Pattern,
  outputs : Array[Match],
) -> Bool {
  for output in outputs {
    if output.pattern != pattern.id || output.key != key {
      continue
    }
    match pattern.after_match {
      NoSkip => ()
      SkipToNextStart =>
        if first == output.occurrences[0] {
          return true
        }
      SkipPastLast => {
        let last = output.occurrences[output.occurrences.length() - 1]
        let event_time = output.last_event_time()
        if started < event_time ||
          (started == event_time && first <= last) {
          return true
        }
      }
    }
  }
  false
}

///|
fn skipped(branch : Branch, pattern : Pattern, outputs : Array[Match]) -> Bool {
  start_skipped(branch.started, first_position(branch), branch.key, pattern, outputs)
}

///|
fn match_order(left : Match, right : Match) -> Int {
  let mut order = left.ended.compare(right.ended)
  if order != 0 { return order }
  order = left.pattern.compare(right.pattern)
  if order != 0 { return order }
  order = left.key.compare(right.key)
  if order != 0 { return order }
  order = left.started.compare(right.started)
  if order != 0 { return order }
  order = left.occurrences[0].compare(right.occurrences[0])
  if order != 0 { return order }
  for i in 0..<left.captures.length() {
    order = left.captures[i].events.length().compare(right.captures[i].events.length())
    if order != 0 { return order }
  }
  for i in 0..<left.occurrences.length() {
    order = left.occurrences[i].compare(right.occurrences[i])
    if order != 0 { return order }
  }
  0
}

///|
fn select_matches(
  candidates : Array[Match],
  patterns : Array[Pattern],
  outputs : Array[Match],
  limits : Limits,
  work : Work,
) -> Unit raise CepError {
  candidates.sort_by(match_order)
  let mut previous : Match? = None
  for candidate in candidates {
    work.charge()
    let duplicate = previous is Some(value) && match_order(value, candidate) == 0
    previous = Some(candidate)
    if duplicate { continue }
    for pattern in patterns {
      if pattern.id == candidate.pattern &&
        !start_skipped(candidate.started, candidate.occurrences[0], candidate.key, pattern, outputs) {
        append_match(outputs, candidate, limits)
      }
    }
  }
}

///|
fn process_item(
  active : Array[Branch],
  item : Stamped,
  patterns : Array[Pattern],
  matches : Array[Match],
  limits : Limits,
  work : Work,
) -> Array[Branch] raise CepError {
  let states : Array[Branch] = []
  let candidates : Array[Match] = []
  let seen : Map[String, Bool] = Map([])
  for branch in active {
    let pattern = patterns[branch.pattern_index]
    if branch.key != item.event.key {
      append_state(states, branch, seen, limits)
    } else if !skipped(branch, pattern, matches) {
      consume_branch(branch, item, pattern, states, candidates, seen, limits, work)
    }
  }
  for index, pattern in patterns {
    work.charge()
    let stage = pattern.stages[0]
    if stage.condition.evaluate(item.event, []) &&
      !(stage.forbidden is Some(c) && c.evaluate(item.event, [])) {
      let captures : Array[Capture] = pattern.stages.map(stage => {
        name: stage.name,
        events: [],
      })
      captures[0].events.push(item.event)
      let branch : Branch = {
        pattern_index: index,
        key: item.event.key,
        stage: 0,
        count: 1,
        captures,
        positions: [item.ordinal],
        started: item.event.time,
        last: item.event.time,
      }
      if !skipped(branch, pattern, matches) {
        expand_branch(branch, pattern, states, candidates, seen, limits, work)
      }
    }
  }
  select_matches(candidates, patterns, matches, limits, work)
  states.filter(branch => !skipped(branch, patterns[branch.pattern_index], matches))
}

///|
fn expire_states(
  active : Array[Branch],
  at : Int64,
  inclusive : Bool,
  patterns : Array[Pattern],
  matches : Array[Match],
  timeouts : Array[Timeout],
  limits : Limits,
  work : Work,
) -> Array[Branch] raise CepError {
  let retained = []
  let expired : Array[Branch] = []
  let candidates : Array[Match] = []
  for branch in active {
    work.charge()
    let pattern = patterns[branch.pattern_index]
    if skipped(branch, pattern, matches) { continue }
    let deadline = branch.started + pattern.within
    if deadline < at || (inclusive && deadline == at) {
      if branch.stage == pattern.stages.length() {
        append_candidate(candidates, make_match(pattern, branch, true), limits)
      } else {
        expired.push(branch)
      }
    } else {
      retained.push(branch)
    }
  }
  select_matches(candidates, patterns, matches, limits, work)
  for branch in expired {
    let pattern = patterns[branch.pattern_index]
    if !skipped(branch, pattern, matches) {
        if timeouts.length() + matches.length() >= limits.outputs_per_call {
          raise Resource(resource="outputs per call", limit=limits.outputs_per_call)
        }
        timeouts.push({
          pattern: pattern.id,
          key: branch.key,
          deadline: branch.started + pattern.within,
          captures: branch.captures,
        })
    }
  }
  retained.filter(branch => !skipped(branch, patterns[branch.pattern_index], matches))
}

///|
/// Close the event-time prefix through W. Any failure leaves the engine unchanged.
pub fn Engine::advance_watermark(self : Engine, requested : Int64) -> Batch raise CepError {
  if requested < self.watermark {
    raise WatermarkRegression(previous=self.watermark, requested~)
  }
  if requested < 0L || requested > 9007230790740991L {
    raise Invalid(path="watermark", reason="expected 0..9007230790740991")
  }
  let buffer = self.buffer.copy()
  let processing = Processing::{ partitions: Map([]), generations: Map([]), deadlines: [], serial: 0, active_count: 0 }
  let grouped : Map[String, Array[Branch]] = Map([])
  for branch in self.active {
    match grouped.get(branch.key) {
      Some(states) => states.push(branch)
      None => grouped.set(branch.key, [branch])
    }
  }
  let matches : Array[Match] = []
  let timeouts : Array[Timeout] = []
  let work = Work::{ used: 0, limit: self.limits.work_per_call }
  for key, states in grouped {
    processing.put(key, states, self.patterns, self.limits, work)
  }
  let mut processed = 0
  while buffer.length() > 0 && buffer[0].event.time <= requested {
    let time = buffer[0].event.time
    processing.expire(time, false, self.patterns, matches, timeouts, self.limits, work)
    while buffer.length() > 0 && buffer[0].event.time == time {
      let item = heap_pop(buffer).unwrap()
      let previous = processing.partitions.get(item.event.key).unwrap_or([])
      let updated = process_item(previous, item, self.patterns, matches, self.limits, work)
      processing.put(item.event.key, updated, self.patterns, self.limits, work)
      processed += 1
    }
    processing.expire(time, true, self.patterns, matches, timeouts, self.limits, work)
  }
  processing.expire(requested, true, self.patterns, matches, timeouts, self.limits, work)
  let active : Array[Branch] = []
  let keys = processing.partitions.keys().collect()
  keys.sort()
  for key in keys {
    for branch in processing.partitions.get(key).unwrap() { active.push(branch) }
  }
  matches.sort_by(match_order)
  timeouts.sort_by((a, b) => {
    let order = a.deadline.compare(b.deadline)
    if order != 0 { order } else {
      let order = a.pattern.compare(b.pattern)
      if order != 0 { order } else { a.key.compare(b.key) }
    }
  })
  if matches.length() + timeouts.length() > self.limits.outputs_per_call {
    raise Resource(resource="outputs per call", limit=self.limits.outputs_per_call)
  }
  self.buffer = buffer
  self.active = active
  self.watermark = requested
  { matches, timeouts, processed, work: work.used }
}

///|
/// Close every possible event and deadline in the documented timestamp domain.
/// A failed finish has the same rollback semantics as advance_watermark.
pub fn Engine::finish(self : Engine) -> Batch raise CepError {
  self.advance_watermark(9007230790740991L)
}
