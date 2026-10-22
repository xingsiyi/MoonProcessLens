///|
pub(all) struct ConditionNote {
  path : String
  passed : Bool
  reason : String
}

///|
pub struct Evaluation {
  result : Bool
  notes : Array[ConditionNote]
}

///|
pub fn Evaluation::matched(self : Evaluation) -> Bool { self.result }

///|
pub fn Evaluation::notes(self : Evaluation) -> Array[ConditionNote] { self.notes.copy() }

///|
fn validate_evaluation(condition : Condition, captures : Array[Capture]) -> Unit raise CepError {
  validate_condition_structure(condition)
  if captures.length() > 32 { raise Resource(resource="evaluation captures", limit=32) }
  let seen : Map[String, Bool] = Map([])
  for capture in captures {
    require_label(capture.name, "evaluation.capture")
    if capture.events.length() > 128 { raise Resource(resource="capture events", limit=128) }
    if seen.contains(capture.name) {
      raise Invalid(path="evaluation.capture", reason="duplicate capture name")
    }
    seen.set(capture.name, true)
  }
}

///|
/// Validate untrusted mutable condition arrays before standalone evaluation.
/// Recognition uses a private fast path over the Pattern's sealed owned AST.
pub fn Condition::evaluate(self : Condition, event : Event, captures : Array[Capture]) -> Bool raise CepError {
  validate_evaluation(self, captures)
  self.evaluate_unchecked(event, captures)
}

///|
fn comparison_reason(left : Value?, right : Value?, passed : Bool) -> String {
  match (left, right) {
    (None, _) | (_, None) => "missing-field"
    (Some(a), Some(b)) =>
      if a.type_name() != b.type_name() { "incompatible-types" }
      else if passed { "accepted" }
      else { "comparison-false" }
  }
}

///|
fn condition_reason(condition : Condition, event : Event, captures : Array[Capture], passed : Bool) -> String {
  if passed { return "accepted" }
  match condition {
    Always => "accepted"
    Kind(_) => "kind-mismatch"
    Has(_) => "missing-field"
    Compare(field, _, value) => comparison_reason(event.field(field), Some(value), passed)
    FieldCompare(a, _, b) => comparison_reason(event.field(a), event.field(b), passed)
    CaptureCompare(field, _, name, other) => {
      match find_condition_capture(captures, name) {
        None => "missing-capture"
        Some(capture) =>
          if capture.events.is_empty() { "empty-capture" } else {
            comparison_reason(event.field(field), capture.events[capture.events.length() - 1].field(other), passed)
          }
      }
    }
    CaptureCount(name, _, _) =>
      if find_condition_capture(captures, name) is None { "missing-capture" } else { "count-comparison-false" }
    TextPrefix(field, _) | TextContains(field, _) =>
      match event.field(field) {
        None => "missing-field"
        Some(Text(_)) => "text-comparison-false"
        _ => "incompatible-types"
      }
    All(_) => "conjunction-false"
    Any(_) => "disjunction-false"
    Not(_) => "negation-false"
  }
}

///|
fn explain_condition(
  condition : Condition,
  event : Event,
  captures : Array[Capture],
  path : String,
  notes : Array[ConditionNote],
) -> Bool {
  let passed = match condition {
    All(children) => {
      let mut passed = true
      for index, child in children {
        // Diagnostic mode deliberately visits every child, including siblings
        // that the Boolean fast path would short-circuit.
        let accepted = explain_condition(child, event, captures, "\{path}.all[\{index}]", notes)
        passed = passed && accepted
      }
      passed
    }
    Any(children) => {
      let mut passed = false
      for index, child in children {
        let accepted = explain_condition(child, event, captures, "\{path}.any[\{index}]", notes)
        passed = passed || accepted
      }
      passed
    }
    Not(child) => !explain_condition(child, event, captures, "\{path}.not", notes)
    _ => condition.evaluate_unchecked(event, captures)
  }
  notes.push({ path, passed, reason: condition_reason(condition, event, captures, passed) })
  passed
}

///|
/// Return value-free diagnostic reasons. Field names and raw values are not
/// copied into the notes; paths refer to condition AST positions.
pub fn Condition::explain(self : Condition, event : Event, captures~ : Array[Capture] = []) -> Evaluation raise CepError {
  validate_evaluation(self, captures)
  let notes = []
  let result = explain_condition(self, event, captures, "condition", notes)
  { result, notes }
}

///|
pub fn evaluation_to_json(evaluation : Evaluation) -> Json {
  {
    "matched": Json::boolean(evaluation.result),
    "notes": Json::array(evaluation.notes.map(note => {
      "path": Json::string(note.path),
      "passed": Json::boolean(note.passed),
      "reason": Json::string(note.reason),
    })),
  }
}
