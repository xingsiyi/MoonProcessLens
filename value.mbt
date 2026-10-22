///|
pub(all) enum Value {
  Text(String)
  Integer(Int64)
  Decimal(Double)
  Boolean(Bool)
  NullValue
} derive(Eq, @debug.Debug)

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub(all) struct Field {
  name : String
  value : Value
} derive(Eq, @debug.Debug)

///|
pub extend Field with Eq::{equal, not_equal}

///|
pub extend Field with @debug.Debug::{to_repr}

///|
pub fn Value::validate(self : Value) -> Unit raise CepError {
  match self {
    Decimal(value) =>
      if !finite(value) {
        raise Invalid(path="value", reason="decimal must be finite")
      }
    Text(value) =>
      if value.length() > 4096 {
        raise Resource(resource="text code units", limit=4096)
      }
    _ => ()
  }
}

///|
pub fn Value::type_name(self : Value) -> String {
  match self {
    Text(_) => "text"
    Integer(_) => "integer"
    Decimal(_) => "decimal"
    Boolean(_) => "boolean"
    NullValue => "null"
  }
}

///|
pub(all) enum Comparison {
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
} derive(Eq, @debug.Debug)

///|
pub extend Comparison with Eq::{equal, not_equal}

///|
pub extend Comparison with @debug.Debug::{to_repr}

///|
fn compare_order(order : Int32, comparison : Comparison) -> Bool {
  match comparison {
    Equal => order == 0
    NotEqual => order != 0
    Less => order < 0
    LessEqual => order <= 0
    Greater => order > 0
    GreaterEqual => order >= 0
  }
}

///|
/// Comparisons never coerce integer values to floating point.
pub fn Value::compare(
  self : Value,
  comparison : Comparison,
  other : Value,
) -> Bool {
  match (self, other) {
    (Integer(a), Integer(b)) => compare_order(a.compare(b), comparison)
    (Decimal(a), Decimal(b)) =>
      finite(a) && finite(b) && compare_order(a.compare(b), comparison)
    (Text(a), Text(b)) => compare_order(a.compare(b), comparison)
    (Boolean(a), Boolean(b)) =>
      match comparison {
        Equal => a == b
        NotEqual => a != b
        _ => false
      }
    (NullValue, NullValue) => comparison == Equal
    _ => false
  }
}
