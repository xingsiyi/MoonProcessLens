///|
pub struct Match {
  pattern : String
  key : String
  captures : Array[Capture]
  occurrences : Array[Int64]
  started : Int64
  ended : Int64
  absence : Bool
}

///|
fn detach_captures(captures : Array[Capture]) -> Array[Capture] {
  captures.map(capture => { name: capture.name, events: capture.events.copy() })
}

///|
pub fn Match::pattern(self : Match) -> String {
  self.pattern
}

///|
pub fn Match::key(self : Match) -> String {
  self.key
}

///|
pub fn Match::captures(self : Match) -> Array[Capture] {
  detach_captures(self.captures)
}

///|
pub fn Match::occurrences(self : Match) -> Array[Int64] {
  self.occurrences.copy()
}

///|
pub fn Match::started(self : Match) -> Int64 {
  self.started
}

///|
pub fn Match::ended(self : Match) -> Int64 {
  self.ended
}

///|
pub fn Match::last_event_time(self : Match) -> Int64 {
  let mut time = self.started
  for capture in self.captures {
    for event in capture.events {
      time = event.time
    }
  }
  time
}

///|
pub fn Match::is_absence(self : Match) -> Bool {
  self.absence
}

///|
pub fn Match::events(self : Match, name : String) -> Array[Event] {
  for capture in self.captures {
    if capture.name == name {
      return capture.events.copy()
    }
  }
  []
}

///|
pub struct Timeout {
  pattern : String
  key : String
  deadline : Int64
  captures : Array[Capture]
}

///|
pub fn Timeout::pattern(self : Timeout) -> String {
  self.pattern
}

///|
pub fn Timeout::key(self : Timeout) -> String {
  self.key
}

///|
pub fn Timeout::deadline(self : Timeout) -> Int64 {
  self.deadline
}

///|
pub fn Timeout::captures(self : Timeout) -> Array[Capture] {
  detach_captures(self.captures)
}

///|
pub struct Batch {
  matches : Array[Match]
  timeouts : Array[Timeout]
  processed : Int
  work : Int
}

///|
pub fn Batch::matches(self : Batch) -> Array[Match] {
  self.matches.map(m => {
    ..m,
    captures: detach_captures(m.captures),
    occurrences: m.occurrences.copy(),
  })
}

///|
pub fn Batch::timeouts(self : Batch) -> Array[Timeout] {
  self.timeouts.map(t => { ..t, captures: detach_captures(t.captures) })
}

///|
pub fn Batch::processed(self : Batch) -> Int {
  self.processed
}

///|
pub fn Batch::work(self : Batch) -> Int {
  self.work
}
