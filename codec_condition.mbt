///|
/// The wire comparison names are stable tokens, independent of display strings.
fn codec_comparison_to_json(comparison : Comparison) -> Json {
  Json::string(
    match comparison {
      Equal => "eq"
      NotEqual => "ne"
      Less => "lt"
      LessEqual => "le"
      Greater => "gt"
      GreaterEqual => "ge"
    },
  )
}

///|
fn codec_comparison_from_json(value : Json, path : String) -> Comparison raise CepError {
  match codec_string(value, path) {
    "eq" => Equal
    "ne" => NotEqual
    "lt" => Less
    "le" => LessEqual
    "gt" => Greater
    "ge" => GreaterEqual
    _ => raise Invalid(path~, reason="expected eq, ne, lt, le, gt or ge")
  }
}

///|
fn codec_text_property(object : Map[String, Json], key : String, path : String) -> String raise CepError {
  codec_string(codec_required(object, key, path), "\{path}.\{key}")
}

///|
fn codec_array(value : Json, path : String) -> Array[Json] raise CepError {
  match value {
    Array(items) => items
    _ => raise Invalid(path~, reason="expected array")
  }
}

///|
/// Small schema counters are JSON integers, never rounded floating-point values.
fn codec_int32(value : Json, path : String) -> Int raise CepError {
  match value {
    Number(number, ..) =>
      if finite(number) && number >= 0.0 && number <= 2147483647.0 {
        let integer = number.to_int()
        if integer.to_double() != number {
          raise Invalid(path~, reason="expected nonnegative Int32 integer")
        }
        integer
      } else {
        raise Invalid(path~, reason="expected nonnegative Int32 integer")
      }
    _ => raise Invalid(path~, reason="expected JSON integer")
  }
}

///|
fn codec_bounded_format(value : Json) -> String raise CepError {
  let text = value.stringify()
  if text.length() > 1048576 {
    raise Resource(resource="JSON UTF-16 code units", limit=1048576)
  }
  text
}

///|
/// This internal traversal is called only after structural validation.
fn codec_condition_to_json(condition : Condition) -> Json {
  match condition {
    Always => { "type": "always" }
    Kind(kind) => { "type": "kind", "value": Json::string(kind) }
    Has(field) => { "type": "has", "field": Json::string(field) }
    Compare(field, comparison, value) => {
      "type": "compare", "field": Json::string(field),
      "op": codec_comparison_to_json(comparison), "value": codec_value_to_json(value),
    }
    FieldCompare(field, comparison, other_field) => {
      "type": "field_compare", "field": Json::string(field),
      "op": codec_comparison_to_json(comparison), "other_field": Json::string(other_field),
    }
    CaptureCompare(field, comparison, capture, captured_field) => {
      "type": "capture_compare", "field": Json::string(field),
      "op": codec_comparison_to_json(comparison), "capture": Json::string(capture),
      "captured_field": Json::string(captured_field),
    }
    CaptureCount(capture, comparison, count) => {
      "type": "capture_count", "capture": Json::string(capture),
      "op": codec_comparison_to_json(comparison), "count": Json::number(count.to_double()),
    }
    TextPrefix(field, text) => {
      "type": "text_prefix", "field": Json::string(field), "text": Json::string(text),
    }
    TextContains(field, text) => {
      "type": "text_contains", "field": Json::string(field), "text": Json::string(text),
    }
    All(children) => {
      "type": "all", "conditions": Json::array(children.map(codec_condition_to_json)),
    }
    Any(children) => {
      "type": "any", "conditions": Json::array(children.map(codec_condition_to_json)),
    }
    Not(child) => { "type": "not", "condition": codec_condition_to_json(child) }
  }
}

///|
pub fn condition_to_json(condition : Condition) -> Json raise CepError {
  validate_condition_structure(condition)
  codec_condition_to_json(condition)
}

///|
priv struct CodecConditionBudget {
  mut nodes : Int
}

///|
/// Depth and node budgets are checked while reading, before allocating an AST.
/// This also terminates when a caller passes a cyclic mutable Json value.
fn codec_read_condition(
  value : Json,
  path : String,
  depth : Int,
  budget : CodecConditionBudget,
) -> Condition raise CepError {
  if depth > 32 {
    raise Resource(resource="condition depth", limit=32)
  }
  budget.nodes += 1
  if budget.nodes > 512 {
    raise Resource(resource="condition nodes", limit=512)
  }
  let object = codec_object(value, path)
  let tag = codec_text_property(object, "type", path)
  match tag {
    "always" => {
      codec_keys(object, ["type"], path)
      Always
    }
    "kind" => {
      codec_keys(object, ["type", "value"], path)
      let kind = codec_text_property(object, "value", path)
      require_label(kind, "\{path}.value")
      Kind(kind)
    }
    "has" => {
      codec_keys(object, ["type", "field"], path)
      let field = codec_text_property(object, "field", path)
      require_label(field, "\{path}.field")
      Has(field)
    }
    "compare" => {
      codec_keys(object, ["type", "field", "op", "value"], path)
      let field = codec_text_property(object, "field", path)
      require_label(field, "\{path}.field")
      let comparison = codec_comparison_from_json(codec_required(object, "op", path), "\{path}.op")
      let scalar = codec_value_from_json(codec_required(object, "value", path), "\{path}.value")
      Compare(field, comparison, scalar)
    }
    "field_compare" => {
      codec_keys(object, ["type", "field", "op", "other_field"], path)
      let field = codec_text_property(object, "field", path)
      let other_field = codec_text_property(object, "other_field", path)
      require_label(field, "\{path}.field")
      require_label(other_field, "\{path}.other_field")
      let comparison = codec_comparison_from_json(codec_required(object, "op", path), "\{path}.op")
      FieldCompare(field, comparison, other_field)
    }
    "capture_compare" => {
      codec_keys(object, ["type", "field", "op", "capture", "captured_field"], path)
      let field = codec_text_property(object, "field", path)
      let capture = codec_text_property(object, "capture", path)
      let captured_field = codec_text_property(object, "captured_field", path)
      require_label(field, "\{path}.field")
      require_label(capture, "\{path}.capture")
      require_label(captured_field, "\{path}.captured_field")
      let comparison = codec_comparison_from_json(codec_required(object, "op", path), "\{path}.op")
      CaptureCompare(field, comparison, capture, captured_field)
    }
    "capture_count" => {
      codec_keys(object, ["type", "capture", "op", "count"], path)
      let capture = codec_text_property(object, "capture", path)
      require_label(capture, "\{path}.capture")
      let comparison = codec_comparison_from_json(codec_required(object, "op", path), "\{path}.op")
      let count = codec_int32(codec_required(object, "count", path), "\{path}.count")
      CaptureCount(capture, comparison, count)
    }
    "text_prefix" | "text_contains" => {
      codec_keys(object, ["type", "field", "text"], path)
      let field = codec_text_property(object, "field", path)
      let text = codec_text_property(object, "text", path)
      require_label(field, "\{path}.field")
      if text.length() > 4096 {
        raise Invalid(path="\{path}.text", reason="text exceeds 4096 UTF-16 code units")
      }
      if tag == "text_prefix" { TextPrefix(field, text) } else { TextContains(field, text) }
    }
    "all" | "any" => {
      codec_keys(object, ["type", "conditions"], path)
      let items = codec_array(codec_required(object, "conditions", path), "\{path}.conditions")
      if items.length() > 512 {
        raise Resource(resource="condition nodes", limit=512)
      }
      let children : Array[Condition] = []
      for index, child in items {
        children.push(codec_read_condition(child, "\{path}.conditions[\{index}]", depth + 1, budget))
      }
      if tag == "all" { All(children) } else { Any(children) }
    }
    "not" => {
      codec_keys(object, ["type", "condition"], path)
      Not(codec_read_condition(codec_required(object, "condition", path), "\{path}.condition", depth + 1, budget))
    }
    _ => raise Invalid(path="\{path}.type", reason="unknown condition type")
  }
}

///|
fn codec_condition_from_json(value : Json, path : String) -> Condition raise CepError {
  let condition = codec_read_condition(value, path, 1, { nodes: 0 })
  validate_condition_structure(condition)
  condition
}

///|
pub fn condition_from_json(value : Json) -> Condition raise CepError {
  codec_condition_from_json(value, "condition")
}

///|
/// Wire nesting allows object/array wrappers around the 32-level AST.
pub fn parse_condition(text : String) -> Condition raise CepError {
  condition_from_json(codec_parse(text, max_depth=128))
}

///|
pub fn format_condition(condition : Condition) -> String raise CepError {
  codec_bounded_format(condition_to_json(condition))
}

