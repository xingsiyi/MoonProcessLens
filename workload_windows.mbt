///|
pub(all) struct ResourceOccupancy {
  started : Int64
  completed : Int64
  active : Int32
}

///|
/// Half-open occupancy for one observed resource, including idle spans.
/// Simultaneous boundaries are folded before sampling; zero-length work adds
/// no occupancy. This is observed concurrency, not staffing utilization.
pub fn EventLog::resource_timeline(
  self : EventLog,
  resource : String,
  from : Int64,
  until : Int64,
  max_segments~ : Int32 = 4096,
) -> Array[ResourceOccupancy] raise ProcessError {
  process_label(resource, "occupancy.resource")
  model_require(
    from >= 0L && until > from && until <= 9007199254740991L,
    "occupancy.window",
    "invalid window",
  )
  model_require(
    max_segments > 0 && max_segments <= 1000000,
    "occupancy.limit",
    "invalid limit",
  )
  let deltas : Map[Int64, Int32] = Map([])
  deltas[from] = 0
  deltas[until] = 0
  for trace in self.traces {
    for event in trace.events {
      if event.resource != Some(resource) ||
        event.completed <= from ||
        event.started >= until ||
        event.completed == event.started {
        continue
      }
      let a = if event.started < from { from } else { event.started }
      let b = if event.completed > until { until } else { event.completed }
      deltas[a] = deltas.get(a).unwrap_or(0) + 1
      deltas[b] = deltas.get(b).unwrap_or(0) - 1
    }
  }
  let points : Array[Int64] = []
  for point, _ in deltas {
    points.push(point)
  }
  points.sort()
  let result : Array[ResourceOccupancy] = []
  let mut active = 0
  for i = 0; i + 1 < points.length(); i = i + 1 {
    active += deltas[points[i]]
    if !result.is_empty() && result[result.length() - 1].active == active {
      let j = result.length() - 1
      result[j] = { ..result[j], completed: points[i + 1], }
    } else {
      if result.length() >= max_segments {
        raise Capacity(resource="occupancy segments", limit=max_segments)
      }
      result.push({ started: points[i], completed: points[i + 1], active, })
    }
  }
  result
}

///|
pub(all) struct FlowWindow {
  started : Int64
  completed : Int64
  cases_started : Int32
  cases_completed : Int32
  active_at_start : Int32
  active_before_end : Int32
  observed_work_area : Double
  mean_observed_wip : Double
  completed_cycles : DurationDistribution
}

///|
/// Fixed-width retrospective windows over whole observed cases. Arrivals and
/// completions use [start,end); occupancy uses case [first-start,last-complete).
/// Open/incomplete cases absent from EventLog cannot be inferred here.
pub fn EventLog::flow_windows(
  self : EventLog,
  from : Int64,
  until : Int64,
  width : Int64,
  max_windows~ : Int32 = 4096,
  max_work~ : Int32 = 10000000,
) -> Array[FlowWindow] raise ProcessError {
  model_require(
    from >= 0L && until > from && until <= 9007199254740991L && width > 0L,
    "flow.window",
    "invalid time window or width",
  )
  model_require(
    max_windows > 0 &&
    max_windows <= 1000000 &&
    max_work > 0 &&
    max_work <= 100000000,
    "flow.limits",
    "invalid limits",
  )
  let count = (until - from - 1L) / width + 1L
  if count > max_windows.to_int64() {
    raise Capacity(resource="flow windows", limit=max_windows)
  }
  if count * self.traces.length().to_int64() > max_work.to_int64() {
    raise Capacity(resource="flow work", limit=max_work)
  }
  let cases : Array[(Int64, Int64)] = []
  for trace in self.traces {
    if trace.events.is_empty() {
      continue
    }
    let start = trace.events[0].started
    cases.push((start, start + trace.cycle_time()))
  }
  let output : Array[FlowWindow] = []
  let mut cursor = from
  while cursor < until {
    let end = if width > until - cursor { until } else { cursor + width }
    let mut arrivals = 0
    let mut completions = 0
    let mut at_start = 0
    let mut before_end = 0
    let mut area = 0.0
    let cycles : Array[Int64] = []
    for (a, b) in cases {
      if a >= cursor && a < end {
        arrivals += 1
      }
      if b >= cursor && b < end {
        completions += 1
        cycles.push(b - a)
      }
      if a <= cursor && b > cursor {
        at_start += 1
      }
      if a < end && b >= end && b > a {
        before_end += 1
      }
      let lo = if a > cursor { a } else { cursor }
      let hi = if b < end { b } else { end }
      if hi > lo {
        area += (hi - lo).to_double()
      }
    }
    output.push({
      started: cursor,
      completed: end,
      cases_started: arrivals,
      cases_completed: completions,
      active_at_start: at_start,
      active_before_end: before_end,
      observed_work_area: area,
      mean_observed_wip: area / (end - cursor).to_double(),
      completed_cycles: duration_distribution(cycles),
    })
    cursor = end
  }
  output
}
