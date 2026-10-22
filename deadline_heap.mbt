///|
priv struct DeadlineEntry {
  time : Int64
  key : String
  generation : Int
}

///|
fn deadline_before(a : DeadlineEntry, b : DeadlineEntry) -> Bool {
  a.time < b.time || (a.time == b.time && a.key < b.key)
}

///|
fn deadline_push(heap : Array[DeadlineEntry], entry : DeadlineEntry) -> Unit {
  heap.push(entry)
  let mut i = heap.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if !deadline_before(heap[i], heap[parent]) { break }
    let saved = heap[i]
    heap[i] = heap[parent]
    heap[parent] = saved
    i = parent
  }
}

///|
fn deadline_pop(heap : Array[DeadlineEntry]) -> DeadlineEntry {
  let first = heap[0]
  let last = heap.pop().unwrap()
  if !heap.is_empty() {
    heap[0] = last
    let mut i = 0
    while i * 2 + 1 < heap.length() {
      let left = i * 2 + 1
      let right = left + 1
      let child = if right < heap.length() && deadline_before(heap[right], heap[left]) { right } else { left }
      if !deadline_before(heap[child], heap[i]) { break }
      let saved = heap[i]
      heap[i] = heap[child]
      heap[child] = saved
      i = child
    }
  }
  first
}

///|
priv struct Processing {
  partitions : Map[String, Array[Branch]]
  generations : Map[String, Int]
  deadlines : Array[DeadlineEntry]
  mut serial : Int
  mut active_count : Int
}

///|
fn Processing::put(
  self : Processing,
  key : String,
  states : Array[Branch],
  patterns : Array[Pattern],
  limits : Limits,
  work : Work,
) -> Unit raise CepError {
  work.charge()
  let previous = self.partitions.get(key).unwrap_or([])
  self.active_count += states.length() - previous.length()
  if self.active_count > limits.active_states {
    raise Resource(resource="active states", limit=limits.active_states)
  }
  self.serial += 1
  self.generations.set(key, self.serial)
  if states.is_empty() {
    self.partitions.remove(key) |> ignore
    return
  }
  self.partitions.set(key, states)
  if self.partitions.length() > limits.partitions {
    raise Resource(resource="partitions", limit=limits.partitions)
  }
  let mut earliest = 9007230790740991L
  for branch in states {
    work.charge()
    earliest = earliest.min(branch.started + patterns[branch.pattern_index].within)
  }
  deadline_push(self.deadlines, { time: earliest, key, generation: self.serial })
}

///|
fn Processing::expire(
  self : Processing,
  at : Int64,
  inclusive : Bool,
  patterns : Array[Pattern],
  matches : Array[Match],
  timeouts : Array[Timeout],
  limits : Limits,
  work : Work,
) -> Unit raise CepError {
  while !self.deadlines.is_empty() &&
    (self.deadlines[0].time < at || (inclusive && self.deadlines[0].time == at)) {
    work.charge()
    let entry = deadline_pop(self.deadlines)
    if self.generations.get(entry.key) != Some(entry.generation) { continue }
    let old = self.partitions.get(entry.key).unwrap_or([])
    let updated = expire_states(old, at, inclusive, patterns, matches, timeouts, limits, work)
    self.put(entry.key, updated, patterns, limits, work)
  }
}
