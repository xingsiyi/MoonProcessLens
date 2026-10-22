///|
/// A pure condition over the current event and previously completed captures.
/// Arrays are detached when a Stage or Pattern is constructed.
pub(all) enum Condition {
  Always
  Kind(String)
  Has(String)
  Compare(String, Comparison, Value)
  FieldCompare(String, Comparison, String)
  CaptureCompare(String, Comparison, String, String)
  CaptureCount(String, Comparison, Int32)
  TextPrefix(String, String)
  TextContains(String, String)
  All(Array[Condition])
  Any(Array[Condition])
  Not(Condition)
} derive(Eq, @debug.Debug)

///|
pub extend Condition with Eq::{equal, not_equal}

///|
pub extend Condition with @debug.Debug::{to_repr}

///|
/// Events captured by one named positive stage, in their matching order.
pub(all) struct Capture {
  name : String
  events : Array[Event]
} derive(Eq, @debug.Debug)

///|
pub extend Capture with Eq::{equal, not_equal}

///|
pub extend Capture with @debug.Debug::{to_repr}

///|
fn validate_capture_reference(
  name : String,
  allowed : Array[String]?,
) -> Unit raise CepError {
  require_label(name, "condition.capture")
  if allowed is Some(names) && !names.contains(name) {
    raise Invalid(
      path="condition.capture",
      reason="capture \{name} must name an earlier stage",
    )
  }
}

///|
fn validate_condition_node(
  condition : Condition,
  allowed : Array[String]?,
  depth : Int32,
  used : Int32,
) -> Int32 raise CepError {
  if depth > 32 {
    raise Resource(resource="condition depth", limit=32)
  }
  let mut nodes = used + 1
  if nodes > 512 {
    raise Resource(resource="condition nodes", limit=512)
  }
  match condition {
    Always => ()
    Kind(kind) => require_label(kind, "condition.kind")
    Has(field) => require_label(field, "condition.field")
    Compare(field, _, value) => {
      require_label(field, "condition.field")
      value.validate()
    }
    FieldCompare(left, _, right) => {
      require_label(left, "condition.field")
      require_label(right, "condition.other_field")
    }
    CaptureCompare(field, _, stage, captured_field) => {
      require_label(field, "condition.field")
      validate_capture_reference(stage, allowed)
      require_label(captured_field, "condition.captured_field")
    }
    CaptureCount(stage, _, count) => {
      validate_capture_reference(stage, allowed)
      if count < 0 {
        raise Invalid(
          path="condition.capture_count",
          reason="capture count must be nonnegative",
        )
      }
    }
    TextPrefix(field, text) | TextContains(field, text) => {
      require_label(field, "condition.field")
      Text(text).validate()
    }
    All(children) | Any(children) =>
      for child in children {
        nodes = validate_condition_node(child, allowed, depth + 1, nodes)
      }
    Not(child) =>
      nodes = validate_condition_node(child, allowed, depth + 1, nodes)
  }
  nodes
}

///|
/// Validates the complete AST, including branches that would short circuit.
/// Depth is at most 32 and the unfolded node count is at most 512. These bounds
/// also reject cyclic arrays before any copying or runtime evaluation occurs.
pub fn Condition::validate(
  self : Condition,
  allowed_captures : Array[String],
) -> Unit raise CepError {
  ignore(validate_condition_node(self, Some(allowed_captures), 1, 0))
}

///|
/// Structural validation is used before stage construction, where the names
/// of earlier captures are not known until the enclosing pattern is built.
fn validate_condition_structure(condition : Condition) -> Unit raise CepError {
  ignore(validate_condition_node(condition, None, 1, 0))
}

///|
/// Detaches every mutable child array. Callers validate before cloning.
fn clone_condition(condition : Condition) -> Condition {
  match condition {
    All(children) => All(children.map(clone_condition))
    Any(children) => Any(children.map(clone_condition))
    Not(child) => Not(clone_condition(child))
    _ => condition
  }
}
