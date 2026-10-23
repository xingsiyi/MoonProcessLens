///|
pub(all) enum ProcessPolicy {
  Response(
    id~ : String,
    trigger~ : String,
    target~ : String,
    within_ms~ : Int64?
  )
  Precedence(id~ : String, trigger~ : String, required~ : String)
  NotCoexist(id~ : String, first~ : String, second~ : String)
  SeparationOfDuties(id~ : String, first~ : String, second~ : String)
}

///|
pub(all) enum PolicyStatus {
  Satisfied
  Violated
  Inconclusive
  NotApplicable
} derive(Eq, @debug.Debug)

///|
pub extend PolicyStatus with Eq::{equal, not_equal}

///|
pub extend PolicyStatus with @debug.Debug::{to_repr}

///|
pub(all) struct PolicyResult {
  case_id : String
  policy : String
  status : PolicyStatus
  event_ids : Array[String]
}

///|
fn ProcessPolicy::identity(self : ProcessPolicy) -> String {
  match self {
    Response(id~, ..)
    | Precedence(id~, ..)
    | NotCoexist(id~, ..)
    | SeparationOfDuties(id~, ..) => id
  }
}

///|
fn ProcessPolicy::labels(self : ProcessPolicy) -> (String, String) {
  match self {
    Response(trigger~, target~, ..) => (trigger, target)
    Precedence(trigger~, required~, ..) => (trigger, required)
    NotCoexist(first~, second~, ..) | SeparationOfDuties(first~, second~, ..) =>
      (first, second)
  }
}

///|
/// Trace-order declarative checks. Response targets must be later occurrences;
/// bounded response requires target.started >= trigger.completed. Missing
/// resource data yields Inconclusive, never a silent separation-of-duty pass.
pub fn EventLog::check_policies(
  self : EventLog,
  policies : Array[ProcessPolicy],
  max_work~ : Int32 = 10000000,
  max_findings~ : Int32 = 100000,
) -> Array[PolicyResult] raise ProcessError {
  model_require(
    max_work >= 1 && max_work <= 100000000,
    "policy.work",
    "invalid work limit",
  )
  model_require(
    max_findings >= 0 && max_findings <= 1000000,
    "policy.findings",
    "invalid evidence limit",
  )
  if policies.length() > 256 {
    raise Capacity(resource="policies", limit=256)
  }
  if self.event_count.to_int64() * policies.length().to_int64() >
    max_work.to_int64() {
    raise Capacity(resource="policy event checks", limit=max_work)
  }
  if self.traces.length().to_int64() * policies.length().to_int64() > 1000000L {
    raise Capacity(resource="policy results", limit=1000000)
  }
  let ids : Map[String, Bool] = Map([])
  for policy in policies {
    let id = policy.identity()
    process_label(id, "policy.id")
    model_require(!ids.contains(id), "policy.id", "duplicate policy")
    ids[id] = true
    let (a, b) = policy.labels()
    process_label(a, "policy.activity")
    process_label(b, "policy.activity")
    match policy {
      Response(within_ms~, ..) =>
        if within_ms is Some(bound) {
          model_require(
            bound >= 0L && bound <= 9007199254740991L,
            "policy.time",
            "invalid duration",
          )
        }
      SeparationOfDuties(..) =>
        model_require(
          a != b,
          "policy.duties",
          "distinct activity labels required",
        )
      _ => ()
    }
  }
  let results = []
  let mut findings = 0
  for trace in self.traces {
    for policy in policies {
      let (a, b) = policy.labels()
      let evidence : Array[String] = []
      let mut applies = false
      let mut incomplete = false
      match policy {
        Response(within_ms~, ..) => {
          let mut next : LogEvent? = None
          let mut index = trace.events.length()
          while index > 0 {
            index -= 1
            let event = trace.events[index]
            if event.activity == a {
              applies = true
              let satisfied = match next {
                None => false
                Some(target) =>
                  match within_ms {
                    None => true
                    Some(bound) =>
                      target.started >= event.completed &&
                      target.started - event.completed <= bound
                  }
              }
              if !satisfied {
                evidence.push(event.id)
              }
            }
            // For time-bounded checks the first target by start time is minimal.
            // An overlapping target cannot satisfy nonnegative gap, but a later
            // non-overlapping target might: bounded lookup handles that below.
            if event.activity == b {
              next = Some(event)
            }
          }
          if within_ms is Some(bound) {
            evidence.clear()
            let targets : Array[(Int32, LogEvent)] = []
            for i, event in trace.events {
              if event.activity == b {
                targets.push((i, event))
              }
            }
            for i, event in trace.events {
              if event.activity != a {
                continue
              }
              // Binary search the earliest target starting no earlier than the
              // trigger completes; position must also be strictly later.
              let mut low = 0
              let mut high = targets.length()
              while low < high {
                let middle = (low + high) / 2
                if targets[middle].1.started < event.completed ||
                  targets[middle].0 <= i {
                  low = middle + 1
                } else {
                  high = middle
                }
              }
              if low >= targets.length() ||
                targets[low].1.started - event.completed > bound {
                evidence.push(event.id)
              }
            }
          }
        }
        Precedence(..) => {
          let mut seen = false
          for event in trace.events {
            if event.activity == a {
              applies = true
              if !seen {
                evidence.push(event.id)
              }
            }
            if event.activity == b {
              seen = true
            }
          }
        }
        NotCoexist(..) => {
          let first = trace.events.filter(event => event.activity == a)
          let second = trace.events.filter(event => event.activity == b)
          applies = !first.is_empty() || !second.is_empty()
          if !first.is_empty() && !second.is_empty() {
            evidence.push(first[0].id)
            evidence.push(second[0].id)
          }
        }
        SeparationOfDuties(..) => {
          let actors : Map[String, String] = Map([])
          let mut first = false
          let mut second = false
          for event in trace.events {
            if event.activity == a {
              first = true
              match event.resource {
                Some(actor) => actors[actor] = event.id
                None => incomplete = true
              }
            }
            if event.activity == b {
              second = true
              if event.resource is None {
                incomplete = true
              }
            }
          }
          applies = first && second
          for event in trace.events {
            if event.activity == b && event.resource is Some(actor) {
              if actors.get(actor) is Some(prior) {
                evidence.push(prior)
                evidence.push(event.id)
              }
            }
          }
        }
      }
      if evidence.length() > max_findings - findings {
        raise Capacity(resource="policy evidence IDs", limit=max_findings)
      }
      findings += evidence.length()
      results.push({
        case_id: trace.id,
        policy: policy.identity(),
        status: if !applies {
          NotApplicable
        } else if !evidence.is_empty() {
          Violated
        } else if incomplete {
          Inconclusive
        } else {
          Satisfied
        },
        event_ids: evidence,
      })
    }
  }
  results
}

///|
pub fn policy_results_to_json(results : Array[PolicyResult]) -> Json {
  Json::array(
    results.map(result => {
      "case_id": result.case_id,
      "policy": result.policy,
      "status": match result.status {
        Satisfied => "satisfied"
        Violated => "violated"
        Inconclusive => "inconclusive"
        NotApplicable => "not_applicable"
      },
      "event_ids": Json::array(result.event_ids.map(Json::string)),
    }),
  )
}
