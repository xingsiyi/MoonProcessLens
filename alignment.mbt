///|
pub struct ReferencePath {
  priv name : String
  priv activities : Array[String]
}

///|
pub fn ReferencePath::new(
  name : String,
  activities : Array[String],
) -> ReferencePath raise ProcessError {
  process_label(name, "reference.name")
  if activities.length() > 4096 {
    raise Capacity(resource="reference activities", limit=4096)
  }
  for activity in activities {
    process_label(activity, "reference.activity")
  }
  { name, activities: activities.copy(), }
}

///|
pub fn ReferencePath::name(self : ReferencePath) -> String {
  self.name
}

///|
pub fn ReferencePath::activities(self : ReferencePath) -> Array[String] {
  self.activities.copy()
}

///|
pub struct AlignmentCosts {
  unexpected : Int32
  missing : Int32
}

///|
pub fn AlignmentCosts::new(
  unexpected~ : Int32 = 1,
  missing~ : Int32 = 1,
) -> AlignmentCosts raise ProcessError {
  if unexpected < 1 || unexpected > 1000 || missing < 1 || missing > 1000 {
    raise InvalidLog(
      path="alignment.costs",
      reason="expected positive costs <= 1000",
    )
  }
  { unexpected, missing, }
}

///|
pub(all) enum AlignmentMove {
  Synchronous(event_id~ : String, activity~ : String)
  Unexpected(event_id~ : String, activity~ : String)
  Missing(activity~ : String)
} derive(Eq, @debug.Debug)

///|
pub extend AlignmentMove with Eq::{equal, not_equal}

///|
pub extend AlignmentMove with @debug.Debug::{to_repr}

///|
pub(all) struct TraceAlignment {
  case_id : String
  reference : String
  cost : Int32
  fitness : Double
  moves : Array[AlignmentMove]
  evaluated_cells : Int32
}

///|
fn align_one(
  trace : CaseTrace,
  reference : ReferencePath,
  costs : AlignmentCosts,
) -> TraceAlignment {
  let n = trace.events.length()
  let m = reference.activities.length()
  let width = m + 1
  let cells = (n + 1) * width
  let table : Array[Int32] = Array::make(cells, 0)
  for i = 1; i <= n; i = i + 1 {
    table[i * width] = i * costs.unexpected
  }
  for j = 1; j <= m; j = j + 1 {
    table[j] = j * costs.missing
  }
  for i = 1; i <= n; i = i + 1 {
    for j = 1; j <= m; j = j + 1 {
      let mut best = table[(i - 1) * width + j] + costs.unexpected
      let missing = table[i * width + j - 1] + costs.missing
      if missing < best {
        best = missing
      }
      if trace.events[i - 1].activity == reference.activities[j - 1] {
        let synchronous = table[(i - 1) * width + j - 1]
        if synchronous < best {
          best = synchronous
        }
      }
      table[i * width + j] = best
    }
  }
  let moves : Array[AlignmentMove] = []
  let mut i = n
  let mut j = m
  while i > 0 || j > 0 {
    if i > 0 &&
      j > 0 &&
      trace.events[i - 1].activity == reference.activities[j - 1] &&
      table[i * width + j] == table[(i - 1) * width + j - 1] {
      let event = trace.events[i - 1]
      moves.push(Synchronous(event_id=event.id, activity=event.activity))
      i = i - 1
      j = j - 1
    } else if i > 0 &&
      table[i * width + j] == table[(i - 1) * width + j] + costs.unexpected {
      let event = trace.events[i - 1]
      moves.push(Unexpected(event_id=event.id, activity=event.activity))
      i = i - 1
    } else {
      moves.push(Missing(activity=reference.activities[j - 1]))
      j = j - 1
    }
  }
  for index = 0; index < moves.length() / 2; index = index + 1 {
    let other = moves.length() - 1 - index
    let saved = moves[index]
    moves[index] = moves[other]
    moves[other] = saved
  }
  let cost = table[n * width + m]
  let baseline = n * costs.unexpected + m * costs.missing
  {
    case_id: trace.id,
    reference: reference.name,
    cost,
    fitness: if baseline == 0 {
      1.0
    } else {
      1.0 - cost.to_double() / baseline.to_double()
    },
    moves,
    evaluated_cells: cells,
  }
}

///|
/// Minimum-cost insertion/deletion alignment against finite reference paths.
/// This is not Petri-net alignment: loops need explicit reference repetitions.
/// Reference ties follow caller order; move ties prefer sync, unexpected, missing.
pub fn CaseTrace::align(
  self : CaseTrace,
  references : Array[ReferencePath],
  costs~ : AlignmentCosts = { unexpected: 1, missing: 1, },
  max_cells~ : Int32 = 1000000,
) -> TraceAlignment raise ProcessError {
  if references.is_empty() || references.length() > 128 {
    raise InvalidLog(
      path="alignment.references",
      reason="expected 1..128 paths",
    )
  }
  if max_cells < 1 || max_cells > 20000000 {
    raise InvalidLog(path="alignment.max_cells", reason="expected 1..20000000")
  }
  let names : Map[String, Bool] = Map([])
  let mut total = 0L
  for reference in references {
    if names.contains(reference.name) {
      raise InvalidLog(path="reference.name", reason="duplicate reference name")
    }
    names.set(reference.name, true)
    total = total +
      (self.events.length() + 1).to_int64() *
      (reference.activities.length() + 1).to_int64()
    if total > max_cells.to_int64() {
      raise Capacity(resource="alignment cells", limit=max_cells)
    }
  }
  let mut best = align_one(self, references[0], costs)
  for index = 1; index < references.length(); index = index + 1 {
    let candidate = align_one(self, references[index], costs)
    if candidate.cost < best.cost {
      best = candidate
    }
  }
  { ..best, evaluated_cells: total.to_int(), }
}

///|
pub fn EventLog::align(
  self : EventLog,
  references : Array[ReferencePath],
  costs~ : AlignmentCosts = { unexpected: 1, missing: 1, },
  max_cells~ : Int32 = 1000000,
) -> Array[TraceAlignment] raise ProcessError {
  if references.is_empty() ||
    references.length() > 128 ||
    max_cells < 1 ||
    max_cells > 20000000 {
    raise InvalidLog(
      path="alignment",
      reason="expected 1..128 references and cell capacity 1..20000000",
    )
  }
  let names : Map[String, Bool] = Map([])
  for reference in references {
    if names.contains(reference.name) {
      raise InvalidLog(path="reference.name", reason="duplicate reference name")
    }
    names.set(reference.name, true)
  }
  let mut total = 0L
  for trace in self.traces {
    for reference in references {
      total = total +
        (trace.events.length() + 1).to_int64() *
        (reference.activities.length() + 1).to_int64()
      if total > max_cells.to_int64() {
        raise Capacity(resource="log alignment cells", limit=max_cells)
      }
    }
  }
  self.traces.map(trace => trace.align(references, costs~, max_cells~))
}

///|
pub fn alignment_to_json(result : TraceAlignment) -> Json {
  let moves : Array[Json] = result.moves.map(step => {
    match step {
      Synchronous(event_id~, activity~) =>
        {
          "move": Json::string("sync"),
          "event_id": Json::string(event_id),
          "activity": Json::string(activity),
        }
      Unexpected(event_id~, activity~) =>
        {
          "move": Json::string("unexpected"),
          "event_id": Json::string(event_id),
          "activity": Json::string(activity),
        }
      Missing(activity~) =>
        { "move": Json::string("missing"), "activity": Json::string(activity) }
    }
  })
  {
    "case_id": Json::string(result.case_id),
    "reference": Json::string(result.reference),
    "cost": Json::number(result.cost.to_double()),
    "fitness": Json::number(result.fitness),
    "evaluated_cells": Json::number(result.evaluated_cells.to_double()),
    "moves": Json::array(moves),
  }
}
