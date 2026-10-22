///|
/// Values are tagged so integer and decimal equality remains type preserving.
fn codec_value_to_json(value : Value) -> Json {
  match value {
    Text(text) => { "type": "text", "value": Json::string(text) }
    Integer(number) => { "type": "integer", "value": Json::string(number.to_string()) }
    Decimal(number) => { "type": "decimal", "value": Json::number(number) }
    Boolean(flag) => { "type": "boolean", "value": Json::boolean(flag) }
    NullValue => { "type": "null" }
  }
}

///|
pub fn value_to_json(value : Value) -> Json raise CepError {
  value.validate()
  codec_value_to_json(value)
}

///|
fn codec_value_from_json(value : Json, path : String) -> Value raise CepError {
  let object = codec_object(value, path)
  let tag = codec_string(codec_required(object, "type", path), "\{path}.type")
  if tag == "null" {
    codec_keys(object, ["type"], path)
    return NullValue
  }
  if tag != "text" && tag != "integer" && tag != "decimal" && tag != "boolean" {
    raise Invalid(path="\{path}.type", reason="unknown scalar type")
  }
  codec_keys(object, ["type", "value"], path)
  let raw = codec_required(object, "value", path)
  let value_path = "\{path}.value"
  match tag {
    "text" => {
      let text = codec_string(raw, value_path)
      if text.length() > 4096 {
        raise Invalid(path=value_path, reason="text exceeds 4096 UTF-16 code units")
      }
      Text(text)
    }
    "integer" => Integer(codec_int64(raw, value_path))
    "decimal" =>
      match raw {
        Number(number, ..) =>
          if finite(number) {
            Decimal(number)
          } else {
            raise Invalid(path=value_path, reason="decimal must be finite")
          }
        _ => raise Invalid(path=value_path, reason="expected JSON number")
      }
    "boolean" => Boolean(codec_boolean(raw, value_path))
    _ => raise Invalid(path="\{path}.type", reason="unknown scalar type")
  }
}

///|
pub fn value_from_json(value : Json) -> Value raise CepError {
  codec_value_from_json(value, "value")
}

