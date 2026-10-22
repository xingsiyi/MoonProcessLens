///|
/// Parse one bounded document. Duplicate keys are rejected before Map construction.
fn codec_parse(text : String, max_depth~ : Int32 = 32) -> Json raise CepError {
  if text.length() > 1048576 {
    raise Resource(resource="JSON UTF-16 code units", limit=1048576)
  }
  @json.parse(text[:], max_nesting_depth=max_depth, reject_duplicate_keys=true) catch {
    err => raise Invalid(path="json", reason=err.to_string())
  }
}

///|
fn codec_object(
  value : Json,
  path : String,
) -> Map[String, Json] raise CepError {
  match value {
    Object(object) => object
    _ => raise Invalid(path~, reason="expected object")
  }
}

///|
fn codec_keys(
  object : Map[String, Json],
  allowed : Array[String],
  path : String,
) -> Unit raise CepError {
  for key, _ in object {
    if !allowed.contains(key) {
      raise Invalid(path="\{path}.\{key}", reason="unknown property")
    }
  }
}

///|
fn codec_required(
  object : Map[String, Json],
  key : String,
  path : String,
) -> Json raise CepError {
  match object.get(key) {
    Some(value) => value
    None =>
      raise Invalid(
        path="\{path}.\{key}",
        reason="required property is missing",
      )
  }
}

///|
fn codec_string(value : Json, path : String) -> String raise CepError {
  match value {
    String(text) => text
    _ => raise Invalid(path~, reason="expected string")
  }
}

///|
fn codec_boolean(value : Json, path : String) -> Bool raise CepError {
  match value {
    True => true
    False => false
    _ => raise Invalid(path~, reason="expected boolean")
  }
}

///|
/// Accumulate negatively so Int64::MIN_VALUE never needs to be negated.
/// Every multiplication and subtraction is checked before it executes.
fn codec_int64(value : Json, path : String) -> Int64 raise CepError {
  let text = codec_string(value, path)
  let chars = text.to_array()
  if chars.length() < 1 || chars.length() > 20 {
    raise Invalid(path~, reason="expected canonical Int64 string")
  }
  let negative = chars[0] == '-'
  let start = if negative { 1 } else { 0 }
  if start == chars.length() {
    raise Invalid(path~, reason="expected digits after minus")
  }
  if chars[start] == '0' && (negative || chars.length() - start > 1) {
    raise Invalid(path~, reason="leading zeros and negative zero are forbidden")
  }
  let limit = if negative {
    -9223372036854775808L
  } else {
    -9223372036854775807L
  }
  let mut total = 0L
  for i in start..<chars.length() {
    let code = chars[i].to_int()
    if code < 48 || code > 57 {
      raise Invalid(path~, reason="expected canonical decimal integer digits")
    }
    let digit = (code - 48).to_int64()
    if total < limit / 10L {
      raise Invalid(path~, reason="integer is outside Int64 range")
    }
    let multiplied = total * 10L
    if multiplied < limit + digit {
      raise Invalid(path~, reason="integer is outside Int64 range")
    }
    total = multiplied - digit
  }
  if negative {
    total
  } else {
    -total
  }
}

///|
fn codec_field_path(path : String, key : String) -> String {
  path + "[" + Json::string(key).stringify() + "]"
}
