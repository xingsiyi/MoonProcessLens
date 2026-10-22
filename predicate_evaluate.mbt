///|
fn find_condition_capture(
  captures : Array[Capture],
  name : String,
) -> Capture? {
  for capture in captures {
    if capture.name == name {
      return Some(capture)
    }
  }
  None
}

///|
fn compare_condition_fields(
  left : Value?,
  comparison : Comparison,
  right : Value?,
) -> Bool {
  match (left, right) {
    (Some(a), Some(b)) => a.compare(comparison, b)
    _ => false
  }
}

///|
/// Evaluates an already validated condition. Missing fields and incompatible
/// types compare false, including NotEqual; Not then uses ordinary Boolean
/// negation. Empty All is true and empty Any is false. A capture field uses its
/// last event; an existing empty optional capture has count zero.
pub fn Condition::evaluate(
  self : Condition,
  event : Event,
  captures : Array[Capture],
) -> Bool {
  match self {
    Always => true
    Kind(kind) => event.kind() == kind
    Has(field) => event.field(field) is Some(_)
    Compare(field, comparison, value) =>
      compare_condition_fields(event.field(field), comparison, Some(value))
    FieldCompare(left, comparison, right) =>
      compare_condition_fields(event.field(left), comparison, event.field(right))
    CaptureCompare(field, comparison, stage, captured_field) => {
      guard find_condition_capture(captures, stage) is Some(capture) else {
        return false
      }
      guard !capture.events.is_empty() else { return false }
      let last = capture.events[capture.events.length() - 1]
      compare_condition_fields(
        event.field(field),
        comparison,
        last.field(captured_field),
      )
    }
    CaptureCount(stage, comparison, count) =>
      match find_condition_capture(captures, stage) {
        Some(capture) => compare_order(capture.events.length().compare(count), comparison)
        None => false
      }
    TextPrefix(field, prefix) =>
      match event.field(field) {
        Some(Text(text)) => text.has_prefix(prefix)
        _ => false
      }
    TextContains(field, part) =>
      match event.field(field) {
        Some(Text(text)) => text.contains(part)
        _ => false
      }
    All(children) => {
      for child in children {
        if !child.evaluate(event, captures) {
          return false
        }
      }
      true
    }
    Any(children) => {
      for child in children {
        if child.evaluate(event, captures) {
          return true
        }
      }
      false
    }
    Not(child) => !child.evaluate(event, captures)
  }
}
