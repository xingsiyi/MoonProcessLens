///|
/// Event timestamps and integer field values are encoded as decimal strings.
pub fn event_to_json(event : Event) -> Json {
  let fields : Map[String, Json] = Map([])
  for field in event.fields() {
    fields[field.name] = codec_value_to_json(field.value)
  }
  {
    "id": Json::string(event.id()),
    "key": Json::string(event.key()),
    "time": Json::string(event.time().to_string()),
    "kind": Json::string(event.kind()),
    "fields": Json::object(fields),
  }
}

///|
pub fn event_from_json(value : Json) -> Event raise CepError {
  let path = "event"
  let object = codec_object(value, path)
  codec_keys(object, ["id", "key", "time", "kind", "fields"], path)
  let id = codec_string(codec_required(object, "id", path), "event.id")
  let key = codec_string(codec_required(object, "key", path), "event.key")
  let time = codec_int64(codec_required(object, "time", path), "event.time")
  let kind = codec_string(codec_required(object, "kind", path), "event.kind")
  let fields : Array[Field] = []
  match object.get("fields") {
    None => ()
    Some(raw) => {
      let source = codec_object(raw, "event.fields")
      if source.length() > 128 {
        raise Resource(resource="event fields", limit=128)
      }
      for name, scalar in source {
        let field_path = codec_field_path("event.fields", name)
        require_label(name, field_path)
        fields.push({ name, value: codec_value_from_json(scalar, field_path), })
      }
    }
  }
  Event::new(id, key, time, kind, fields~)
}

///|
pub fn parse_event(text : String) -> Event raise CepError {
  event_from_json(codec_parse(text))
}

///|
/// Format any valid event. The text parser separately enforces a 1 Mi-unit input limit.
pub fn format_event(event : Event) -> String {
  event_to_json(event).stringify()
}

///|
/// Format an event only when its escaped JSON fits the bounded text parser.
pub fn checked_format_event(event : Event) -> String raise CepError {
  let text = format_event(event)
  if text.length() > 1048576 {
    raise Resource(resource="JSON UTF-16 code units", limit=1048576)
  }
  text
}
