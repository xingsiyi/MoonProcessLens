///|
pub(all) suberror CepError {
  Invalid(path~ : String, reason~ : String)
  Resource(resource~ : String, limit~ : Int32)
  LateEvent(time~ : Int64, watermark~ : Int64)
  WatermarkRegression(previous~ : Int64, requested~ : Int64)
} derive(@debug.Debug)

///|
pub extend CepError with @debug.Debug::{to_repr}

///|
pub fn CepError::message(self : CepError) -> String {
  match self {
    Invalid(path~, reason~) => "\{path}: \{reason}"
    Resource(resource~, limit~) => "\{resource} limit \{limit} exceeded"
    LateEvent(time~, watermark~) =>
      "event time \{time} is at or below watermark \{watermark}"
    WatermarkRegression(previous~, requested~) =>
      "watermark \{requested} precedes \{previous}"
  }
}

///|
fn require_label(value : String, path : String) -> Unit raise CepError {
  if value.length() == 0 || value.length() > 256 {
    raise Invalid(path~, reason="expected 1..256 UTF-16 code units")
  }
  for ch in value {
    if ch.to_int() < 32 || ch.to_int() == 127 {
      raise Invalid(path~, reason="ASCII controls are forbidden")
    }
  }
}

///|
fn finite(value : Double) -> Bool {
  value == value && value <= @double.max_value && value >= @double.min_value
}
