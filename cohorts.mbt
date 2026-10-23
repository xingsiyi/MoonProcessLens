///|
pub(all) struct CaseSelection {
  require_activities : Array[String]
  exclude_activities : Array[String]
  minimum_cycle : Int64?
  maximum_cycle : Int64?
  starts_from : Int64?
  starts_before : Int64?
}

///|
pub fn CaseSelection::all() -> CaseSelection {
  {
    require_activities: [],
    exclude_activities: [],
    minimum_cycle: None,
    maximum_cycle: None,
    starts_from: None,
    starts_before: None,
  }
}

///|
/// Select WHOLE cases, never truncate histories or synthesize missing events.
/// Window is start-inclusive/end-exclusive in the caller's interval time unit.
pub fn EventLog::select_cases(
  self : EventLog,
  selection : CaseSelection,
) -> EventLog raise ProcessError {
  if selection.require_activities.length() +
    selection.exclude_activities.length() >
    256 {
    raise Capacity(resource="selection activities", limit=256)
  }
  for
    option in [
      selection.minimum_cycle,
      selection.maximum_cycle,
      selection.starts_from,
      selection.starts_before,
    ] {
    if option is Some(value) {
      model_require(value >= 0L, "selection", "negative selection bound")
    }
  }
  if (selection.minimum_cycle, selection.maximum_cycle)
    is (Some(low), Some(high)) {
    model_require(low <= high, "selection", "inverted duration bounds")
  }
  if (selection.starts_from, selection.starts_before) is (Some(low), Some(high)) {
    model_require(low <= high, "selection", "inverted time window")
  }
  for activity in selection.require_activities {
    process_label(activity, "selection.activity")
  }
  for activity in selection.exclude_activities {
    process_label(activity, "selection.activity")
  }
  let traces = []
  let mut events = 0
  for trace in self.traces {
    let activities = trace.activities()
    let duration = trace.cycle_time()
    if !selection.require_activities.all(a => activities.contains(a)) ||
      selection.exclude_activities.any(a => activities.contains(a)) {
      continue
    }
    if selection.minimum_cycle is Some(minimum) {
      if duration < minimum {
        continue
      }
    }
    if selection.maximum_cycle is Some(maximum) {
      if duration > maximum {
        continue
      }
    }
    if selection.starts_from is Some(low) {
      if trace.events.is_empty() || trace.events[0].started < low {
        continue
      }
    }
    if selection.starts_before is Some(high) {
      if trace.events.is_empty() || trace.events[0].started >= high {
        continue
      }
    }
    traces.push(trace)
    events += trace.events.length()
  }
  { traces, event_count: events, }
}

///|
pub(all) struct ResourceHandoff {
  source : String
  target : String
  occurrences : Int32
  cases : Int32
}

///|
/// Adjacent observed resource handovers, excluding self-handover and missing
/// resources. Descriptive only: adjacency does not prove a causal transfer.
pub fn EventLog::resource_handoffs(self : EventLog) -> Array[ResourceHandoff] {
  let edges : Map[String, ResourceHandoff] = Map([])
  for trace in self.traces {
    let seen : Map[String, Bool] = Map([])
    for i in 1..<trace.events.length() {
      if (trace.events[i - 1].resource, trace.events[i].resource)
        is (Some(source), Some(target)) {
        if source == target {
          continue
        }
        let key = path_identity([source, target])
        let old = edges
          .get(key)
          .unwrap_or({ source, target, occurrences: 0, cases: 0, })
        edges[key] = {
          ..old,
          occurrences: old.occurrences + 1,
          cases: old.cases + (if seen.contains(key) { 0 } else { 1 }),
        }
        seen[key] = true
      }
    }
  }
  let result = edges.values().collect()
  result.sort_by((a, b) => {
    let order = a.source.lexical_compare(b.source)
    if order == 0 {
      a.target.lexical_compare(b.target)
    } else {
      order
    }
  })
  result
}

///|
pub(all) struct VariantDelta {
  activities : Array[String]
  before_cases : Int32
  after_cases : Int32
}

///|
pub(all) struct CohortComparison {
  before_cases : Int32
  after_cases : Int32
  total_variation : Double
  variants : Array[VariantDelta]
}

///|
/// Compare normalized variant distributions (total variation distance 0..1).
/// Requires two nonempty cohorts; this is descriptive drift, not a p-value or
/// a causal explanation. Frequency and full variant sequence are retained.
pub fn EventLog::compare_cohort(
  self : EventLog,
  next : EventLog,
) -> CohortComparison raise ProcessError {
  model_require(
    !self.traces.is_empty() && !next.traces.is_empty(),
    "cohort",
    "nonempty cohorts required",
  )
  let variants : Map[String, VariantDelta] = Map([])
  for variant in self.discover().variants {
    variants[path_identity(variant.activities)] = {
      activities: variant.activities,
      before_cases: variant.cases.length(),
      after_cases: 0,
    }
  }
  for variant in next.discover().variants {
    let key = path_identity(variant.activities)
    let row = variants
      .get(key)
      .unwrap_or({
        activities: variant.activities,
        before_cases: 0,
        after_cases: 0,
      })
    variants[key] = { ..row, after_cases: variant.cases.length(), }
  }
  let keys = variants.keys().collect()
  keys.sort_by((a, b) => a.lexical_compare(b))
  let result = []
  let mut difference = 0.0
  for key in keys {
    let row = variants[key]
    difference += (row.before_cases.to_double() /
    self.traces.length().to_double() -
    row.after_cases.to_double() / next.traces.length().to_double()).abs()
    result.push(row)
  }
  {
    before_cases: self.traces.length(),
    after_cases: next.traces.length(),
    total_variation: difference / 2.0,
    variants: result,
  }
}
