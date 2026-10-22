///|
pub(all) struct DurationDistribution {
  count : Int32
  minimum : Int64?
  maximum : Int64?
  median : Int64?
  p95 : Int64?
  mean : Double?
}

///|
fn duration_distribution(samples : Array[Int64]) -> DurationDistribution {
  if samples.is_empty() {
    return {
      count: 0,
      minimum: None,
      maximum: None,
      median: None,
      p95: None,
      mean: None,
    }
  }
  let ordered = samples.copy()
  ordered.sort()
  let mut mean = 0.0
  for i, value in ordered {
    mean = mean + (value.to_double() - mean) / (i + 1).to_double()
  }
  let size = ordered.length()
  {
    count: size,
    minimum: Some(ordered[0]),
    maximum: Some(ordered[size - 1]),
    median: Some(ordered[(size * 50 + 99) / 100 - 1]),
    p95: Some(ordered[(size * 95 + 99) / 100 - 1]),
    mean: Some(mean),
  }
}

///|
pub(all) struct CasePerformance {
  case_id : String
  events : Int32
  cycle_time : Int64
  busy_union : Int64
  idle_time : Int64
  service_work : Double
  overlapping_starts : Int32
}

///|
pub(all) struct ActivityPerformance {
  activity : String
  service : DurationDistribution
}

///|
pub(all) struct HandoffPerformance {
  source : String
  target : String
  positive_gap : DurationDistribution
  overlapping_pairs : Int32
}

///|
pub(all) struct ResourcePerformance {
  resource : String
  occurrences : Int32
  service : DurationDistribution
  maximum_concurrency : Int32
}

///|
pub(all) struct PerformanceReport {
  cases : Array[CasePerformance]
  activities : Array[ActivityPerformance]
  handoffs : Array[HandoffPerformance]
  resources : Array[ResourcePerformance]
  cycle_times : DurationDistribution
}

///|
/// Busy time is interval union, not the sum of concurrent service durations.
pub fn CaseTrace::performance(self : CaseTrace) -> CasePerformance {
  let mut cursor = if self.events.is_empty() {
    0L
  } else {
    self.events[0].started
  }
  let mut busy = 0L
  let mut work = 0.0
  let mut overlapping = 0
  for event in self.events {
    work = work + (event.completed - event.started).to_double()
    if event.completed > event.started && event.started < cursor {
      overlapping = overlapping + 1
    }
    if event.completed > cursor {
      let start = if event.started > cursor { event.started } else { cursor }
      busy = busy + event.completed - start
      cursor = event.completed
    }
  }
  let cycle = self.cycle_time()
  {
    case_id: self.id,
    events: self.events.length(),
    cycle_time: cycle,
    busy_union: busy,
    idle_time: cycle - busy,
    service_work: work,
    overlapping_starts: overlapping,
  }
}

///|
fn resource_concurrency(events : Array[LogEvent]) -> Int32 {
  let points : Array[(Int64, Int32)] = []
  for event in events {
    if event.completed > event.started {
      points.push((event.started, 1))
      points.push((event.completed, -1))
    }
  }
  points.sort_by((a, b) => {
    let time = a.0.compare(b.0)
    if time != 0 {
      time
    } else {
      a.1.compare(b.1)
    }
  })
  let mut current = 0
  let mut maximum = 0
  for point in points {
    current = current + point.1
    if current > maximum {
      maximum = current
    }
  }
  maximum
}

///|
/// Handoffs are descriptive adjacent-activity gaps. Overlapping pairs contribute
/// zero to the gap distribution and are counted separately. They are not proof
/// of causality. Resource concurrency is observed workload, not utilization.
pub fn EventLog::performance(self : EventLog) -> PerformanceReport {
  let activities : Map[String, Array[Int64]] = Map([])
  let resources : Map[String, Array[LogEvent]] = Map([])
  let gaps : Map[String, Array[Int64]] = Map([])
  let handoff_names : Map[String, (String, String)] = Map([])
  let overlaps : Map[String, Int32] = Map([])
  let cases = self.traces.map(CaseTrace::performance)
  for trace in self.traces {
    for i, event in trace.events {
      let samples = activities.get(event.activity).unwrap_or([])
      samples.push(event.completed - event.started)
      activities.set(event.activity, samples)
      if event.resource is Some(resource) {
        let grouped = resources.get(resource).unwrap_or([])
        grouped.push(event)
        resources.set(resource, grouped)
      }
      if i > 0 {
        let previous = trace.events[i - 1]
        let key = path_identity([previous.activity, event.activity])
        handoff_names.set(key, (previous.activity, event.activity))
        let delay = event.started - previous.completed
        let samples = gaps.get(key).unwrap_or([])
        samples.push(if delay > 0L { delay } else { 0L })
        gaps.set(key, samples)
        if delay < 0L {
          overlaps.set(key, overlaps.get(key).unwrap_or(0) + 1)
        }
      }
    }
  }
  let activity_rows = activities
    .iter()
    .map(item => { activity: item.0, service: duration_distribution(item.1), })
    .collect()
  activity_rows.sort_by((a, b) => a.activity.lexical_compare(b.activity))
  let resource_rows = resources
    .iter()
    .map(item => {
      resource: item.0,
      occurrences: item.1.length(),
      service: duration_distribution(
        item.1.map(event => event.completed - event.started),
      ),
      maximum_concurrency: resource_concurrency(item.1),
    })
    .collect()
  resource_rows.sort_by((a, b) => a.resource.lexical_compare(b.resource))
  let handoff_rows = gaps
    .iter()
    .map(item => {
      let names = handoff_names.get(item.0).unwrap()
      HandoffPerformance::{
        source: names.0,
        target: names.1,
        positive_gap: duration_distribution(item.1),
        overlapping_pairs: overlaps.get(item.0).unwrap_or(0),
      }
    })
    .collect()
  handoff_rows.sort_by((a, b) => {
    let source = a.source.lexical_compare(b.source)
    if source != 0 {
      source
    } else {
      a.target.lexical_compare(b.target)
    }
  })
  {
    cases,
    activities: activity_rows,
    handoffs: handoff_rows,
    resources: resource_rows,
    cycle_times: duration_distribution(cases.map(row => row.cycle_time)),
  }
}

///|
fn optional_duration(value : Int64?) -> Json {
  match value {
    Some(value) => Json::string(value.to_string())
    None => Json::null()
  }
}

///|
fn distribution_to_json(value : DurationDistribution) -> Json {
  {
    "count": Json::number(value.count.to_double()),
    "minimum": optional_duration(value.minimum),
    "maximum": optional_duration(value.maximum),
    "median": optional_duration(value.median),
    "p95": optional_duration(value.p95),
    "mean": match value.mean {
      Some(mean) => Json::number(mean)
      None => Json::null()
    },
  }
}

///|
pub fn performance_to_json(report : PerformanceReport) -> Json {
  let cases : Array[Json] = report.cases.map(row => {
    "case_id": Json::string(row.case_id),
    "events": Json::number(row.events.to_double()),
    "cycle_time": Json::string(row.cycle_time.to_string()),
    "busy_union": Json::string(row.busy_union.to_string()),
    "idle_time": Json::string(row.idle_time.to_string()),
    "service_work": Json::number(row.service_work),
    "overlapping_starts": Json::number(row.overlapping_starts.to_double()),
  })
  let activities : Array[Json] = report.activities.map(row => {
    "activity": Json::string(row.activity),
    "service": distribution_to_json(row.service),
  })
  let handoffs : Array[Json] = report.handoffs.map(row => {
    "source": Json::string(row.source),
    "target": Json::string(row.target),
    "positive_gap": distribution_to_json(row.positive_gap),
    "overlapping_pairs": Json::number(row.overlapping_pairs.to_double()),
  })
  let resources : Array[Json] = report.resources.map(row => {
    "resource": Json::string(row.resource),
    "occurrences": Json::number(row.occurrences.to_double()),
    "service": distribution_to_json(row.service),
    "maximum_concurrency": Json::number(row.maximum_concurrency.to_double()),
  })
  {
    "cases": Json::array(cases),
    "activities": Json::array(activities),
    "handoffs": Json::array(handoffs),
    "resources": Json::array(resources),
    "cycle_times": distribution_to_json(report.cycle_times),
  }
}
