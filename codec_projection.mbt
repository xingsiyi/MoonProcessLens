///|
fn projection_tag(projection : Projection) -> String {
  match projection {
    EntityKey => "entity_key"
    PatternName => "pattern_name"
    StartTime => "start_time"
    EndTime => "end_time"
    Duration => "duration"
    AbsenceMatch => "absence"
    CaptureSize(_) => "capture_size"
    FirstField(_, _) => "first"
    LastField(_, _) => "last"
    TotalInteger(_, _) => "sum_integer"
    TotalDecimal(_, _) => "sum_decimal"
    MinimumField(_, _) => "minimum"
    MaximumField(_, _) => "maximum"
    AverageDecimal(_, _) => "average_decimal"
  }
}

///|
pub fn projection_to_json(plan : ProjectionPlan) -> Json {
  {
    "schema_version": 1,
    "pattern": Json::string(plan.pattern),
    "columns": Json::array(
      plan.columns.map(column => {
        let fields : Map[String, Json] = Map([
          ("name", Json::string(column.name)),
          ("type", Json::string(projection_tag(column.projection))),
        ])
        if projection_capture(column.projection) is Some(name) {
          fields.set("capture", Json::string(name))
        }
        if projection_field(column.projection) is Some(name) {
          fields.set("field", Json::string(name))
        }
        Json::object(fields)
      }),
    ),
  }
}

///|
fn projection_from_column(value : Json, path : String) -> Column raise CepError {
  let object = codec_object(value, path)
  let name = codec_text_property(object, "name", path)
  let tag = codec_text_property(object, "type", path)
  let projection = match tag {
    "entity_key"
    | "pattern_name"
    | "start_time"
    | "end_time"
    | "duration"
    | "absence" => {
      codec_keys(object, ["name", "type"], path)
      match tag {
        "entity_key" => EntityKey
        "pattern_name" => PatternName
        "start_time" => StartTime
        "end_time" => EndTime
        "duration" => Duration
        _ => AbsenceMatch
      }
    }
    "capture_size" => {
      codec_keys(object, ["name", "type", "capture"], path)
      CaptureSize(codec_text_property(object, "capture", path))
    }
    "first"
    | "last"
    | "sum_integer"
    | "sum_decimal"
    | "minimum"
    | "maximum"
    | "average_decimal" => {
      codec_keys(object, ["name", "type", "capture", "field"], path)
      let capture = codec_text_property(object, "capture", path)
      let field = codec_text_property(object, "field", path)
      match tag {
        "first" => FirstField(capture, field)
        "last" => LastField(capture, field)
        "sum_integer" => TotalInteger(capture, field)
        "sum_decimal" => TotalDecimal(capture, field)
        "minimum" => MinimumField(capture, field)
        "maximum" => MaximumField(capture, field)
        _ => AverageDecimal(capture, field)
      }
    }
    _ => raise Invalid(path="\{path}.type", reason="unknown projection type")
  }
  { name, projection, }
}

///|
pub fn projection_from_json(
  pattern : Pattern,
  value : Json,
) -> ProjectionPlan raise CepError {
  let object = codec_object(value, "projection")
  codec_keys(object, ["schema_version", "pattern", "columns"], "projection")
  if codec_int32(
      codec_required(object, "schema_version", "projection"),
      "projection.schema_version",
    ) !=
    1 {
    raise Invalid(
      path="projection.schema_version",
      reason="only version 1 is supported",
    )
  }
  if codec_text_property(object, "pattern", "projection") != pattern.id {
    raise Invalid(
      path="projection.pattern",
      reason="projection targets a different pattern",
    )
  }
  let items = codec_array(
    codec_required(object, "columns", "projection"),
    "projection.columns",
  )
  if items.length() > 128 {
    raise Resource(resource="projection columns", limit=128)
  }
  let columns = []
  for index, item in items {
    columns.push(projection_from_column(item, "projection.columns[\{index}]"))
  }
  ProjectionPlan::new(pattern, columns)
}

///|
pub fn projected_record_to_json(fields : Array[Field]) -> Json raise CepError {
  if fields.length() > 128 {
    raise Resource(resource="record fields", limit=128)
  }
  let object : Map[String, Json] = Map([])
  for field in fields {
    require_label(field.name, "record.field")
    field.value.validate()
    if object.contains(field.name) {
      raise Invalid(path="record", reason="duplicate record field")
    }
    object.set(field.name, codec_value_to_json(field.value))
  }
  Json::object(object)
}
