///|
fn codec_stage_to_json(stage : Stage) -> Json {
  let object : Map[String, Json] = Map([
    ("name", Json::string(stage.name)),
    ("condition", codec_condition_to_json(stage.condition)),
    ("min", Json::number(stage.min.to_double())),
    ("max", Json::number(stage.max.to_double())),
    ("contiguity", Json::string(match stage.contiguity {
      Strict => "strict"
      SkipNext => "skip_next"
      SkipAny => "skip_any"
    })),
  ])
  if stage.forbidden is Some(condition) {
    object.set("forbidden", codec_condition_to_json(condition))
  }
  Json::object(object)
}

///|
fn codec_stage_from_json(value : Json, path : String) -> Stage raise CepError {
  let object = codec_object(value, path)
  codec_keys(object, ["name", "condition", "min", "max", "contiguity", "forbidden"], path)
  let name = codec_text_property(object, "name", path)
  let condition = codec_condition_from_json(codec_required(object, "condition", path), "\{path}.condition")
  let min = codec_int32(codec_required(object, "min", path), "\{path}.min")
  let max = codec_int32(codec_required(object, "max", path), "\{path}.max")
  let contiguity = match codec_text_property(object, "contiguity", path) {
    "strict" => Strict
    "skip_next" => SkipNext
    "skip_any" => SkipAny
    _ => raise Invalid(path="\{path}.contiguity", reason="unknown contiguity")
  }
  let forbidden = object.get("forbidden").map(value => codec_condition_from_json(value, "\{path}.forbidden"))
  Stage::new(name, condition, min~, max~, contiguity~, forbidden?)
}

///|
pub fn pattern_to_json(pattern : Pattern) -> Json {
  let object : Map[String, Json] = Map([
    ("schema_version", Json::number(1.0)),
    ("id", Json::string(pattern.id)),
    ("within", Json::string(pattern.within.to_string())),
    ("after_match", Json::string(match pattern.after_match {
      NoSkip => "no_skip"
      SkipToNextStart => "skip_to_next_start"
      SkipPastLast => "skip_past_last"
    })),
    ("stages", Json::array(pattern.stages.map(codec_stage_to_json))),
  ])
  if pattern.absence is Some(condition) {
    object.set("absence", codec_condition_to_json(condition))
  }
  Json::object(object)
}

///|
pub fn pattern_from_json(value : Json) -> Pattern raise CepError {
  let path = "pattern"
  let object = codec_object(value, path)
  codec_keys(object, ["schema_version", "id", "within", "after_match", "stages", "absence"], path)
  if codec_int32(codec_required(object, "schema_version", path), "pattern.schema_version") != 1 {
    raise Invalid(path="pattern.schema_version", reason="only version 1 is supported")
  }
  let id = codec_text_property(object, "id", path)
  let within = codec_int64(codec_required(object, "within", path), "pattern.within")
  let after_match = match codec_text_property(object, "after_match", path) {
    "no_skip" => NoSkip
    "skip_to_next_start" => SkipToNextStart
    "skip_past_last" => SkipPastLast
    _ => raise Invalid(path="pattern.after_match", reason="unknown match selection policy")
  }
  let items = codec_array(codec_required(object, "stages", path), "pattern.stages")
  if items.length() > 32 {
    raise Resource(resource="pattern stages", limit=32)
  }
  let stages = []
  for index, item in items {
    stages.push(codec_stage_from_json(item, "pattern.stages[\{index}]"))
  }
  let absence = object.get("absence").map(value => codec_condition_from_json(value, "pattern.absence"))
  Pattern::new(id, stages, within, after_match~, absence?)
}

///|
pub fn parse_pattern(text : String) -> Pattern raise CepError {
  pattern_from_json(codec_parse(text, max_depth=128))
}

///|
pub fn format_pattern(pattern : Pattern) -> String raise CepError {
  codec_bounded_format(pattern_to_json(pattern))
}
