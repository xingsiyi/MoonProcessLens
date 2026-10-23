///|
pub(all) suberror ProcessError {
  InvalidLog(path~ : String, reason~ : String)
  Capacity(resource~ : String, limit~ : Int32)
} derive(@debug.Debug)

///|
pub extend ProcessError with @debug.Debug::{to_repr}

///|
fn process_label(value : String, path : String) -> Unit raise ProcessError {
  if value.is_empty() || value.length() > 256 {
    raise InvalidLog(path~, reason="expected 1..256 UTF-16 units")
  }
  for ch in value {
    if ch.to_int() < 32 || ch.to_int() == 127 {
      raise InvalidLog(path~, reason="control characters are forbidden")
    }
  }
}

///|
/// A completed activity occurrence. Intervals may overlap within a case.
pub struct LogEvent {
  id : String
  case_id : String
  activity : String
  started : Int64
  completed : Int64
  resource : String?
} derive(Eq, @debug.Debug)

///|
pub extend LogEvent with Eq::{equal, not_equal}

///|
pub extend LogEvent with @debug.Debug::{to_repr}

///|
pub fn LogEvent::new(
  id : String,
  case_id : String,
  activity : String,
  started : Int64,
  completed : Int64,
  resource~ : String? = None,
) -> LogEvent raise ProcessError {
  process_label(id, "event.id")
  process_label(case_id, "event.case_id")
  process_label(activity, "event.activity")
  if started < 0L || completed < started || completed > 9007199254740991L {
    raise InvalidLog(
      path="event.interval",
      reason="expected 0 <= started <= completed <= 9007199254740991",
    )
  }
  if resource is Some(value) {
    process_label(value, "event.resource")
  }
  { id, case_id, activity, started, completed, resource, }
}

///|
pub fn LogEvent::id(self : LogEvent) -> String {
  self.id
}

///|
pub fn LogEvent::case_id(self : LogEvent) -> String {
  self.case_id
}

///|
pub fn LogEvent::activity(self : LogEvent) -> String {
  self.activity
}

///|
pub fn LogEvent::started(self : LogEvent) -> Int64 {
  self.started
}

///|
pub fn LogEvent::completed(self : LogEvent) -> Int64 {
  self.completed
}

///|
pub fn LogEvent::resource(self : LogEvent) -> String? {
  self.resource
}

///|
pub struct CaseTrace {
  priv id : String
  priv events : Array[LogEvent]
}

///|
pub fn CaseTrace::new(
  id : String,
  events : Array[LogEvent],
) -> CaseTrace raise ProcessError {
  process_label(id, "trace.id")
  for event in events {
    if event.case_id != id {
      raise InvalidLog(
        path="trace.events",
        reason="event belongs to another case",
      )
    }
  }
  if events.is_empty() {
    return { id, events: [], }
  }
  EventLog::new(events, max_cases=1).traces[0]
}

///|
pub fn CaseTrace::id(self : CaseTrace) -> String {
  self.id
}

///|
pub fn CaseTrace::events(self : CaseTrace) -> Array[LogEvent] {
  self.events.copy()
}

///|
pub fn CaseTrace::activities(self : CaseTrace) -> Array[String] {
  self.events.map(event => event.activity)
}

///|
pub fn CaseTrace::cycle_time(self : CaseTrace) -> Int64 {
  if self.events.is_empty() {
    return 0L
  }
  let mut completed = self.events[0].completed
  for event in self.events {
    if event.completed > completed {
      completed = event.completed
    }
  }
  completed - self.events[0].started
}

///|
pub struct EventLog {
  priv traces : Array[CaseTrace]
  priv event_count : Int32
}

///|
/// Sort by start time, completion time, then original input occurrence.
/// Event IDs are globally unique; case IDs are opaque and sorted lexically.
pub fn EventLog::new(
  events : Array[LogEvent],
  max_events~ : Int32 = 100000,
  max_cases~ : Int32 = 10000,
  max_trace~ : Int32 = 4096,
) -> EventLog raise ProcessError {
  if max_events < 1 ||
    max_events > 1000000 ||
    max_cases < 1 ||
    max_cases > 100000 ||
    max_trace < 1 ||
    max_trace > 10000 {
    raise InvalidLog(path="log.limits", reason="invalid bounded log capacity")
  }
  if events.length() > max_events {
    raise Capacity(resource="log events", limit=max_events)
  }
  let ids : Map[String, Bool] = Map([])
  let groups : Map[String, Array[(Int32, LogEvent)]] = Map([])
  for index, event in events {
    if ids.contains(event.id) {
      raise InvalidLog(path="event.id", reason="duplicate event id")
    }
    ids.set(event.id, true)
    let group = match groups.get(event.case_id) {
      Some(group) => group
      None => {
        if groups.length() >= max_cases {
          raise Capacity(resource="log cases", limit=max_cases)
        }
        let group : Array[(Int32, LogEvent)] = []
        groups.set(event.case_id, group)
        group
      }
    }
    if group.length() >= max_trace {
      raise Capacity(resource="case events", limit=max_trace)
    }
    group.push((index, event))
  }
  let keys = groups.keys().collect()
  keys.sort_by((a, b) => a.lexical_compare(b))
  let traces : Array[CaseTrace] = []
  for id in keys {
    let group = groups.get(id).unwrap()
    group.sort_by((a, b) => {
      let start = a.1.started.compare(b.1.started)
      if start != 0 {
        start
      } else {
        let end = a.1.completed.compare(b.1.completed)
        if end != 0 {
          end
        } else {
          a.0.compare(b.0)
        }
      }
    })
    traces.push({ id, events: group.map(item => item.1), })
  }
  { traces, event_count: events.length(), }
}

///|
pub fn EventLog::traces(self : EventLog) -> Array[CaseTrace] {
  self.traces.map(trace => { ..trace, events: trace.events.copy(), })
}

///|
pub fn EventLog::event_count(self : EventLog) -> Int32 {
  self.event_count
}

///|
pub fn EventLog::case_count(self : EventLog) -> Int32 {
  self.traces.length()
}
