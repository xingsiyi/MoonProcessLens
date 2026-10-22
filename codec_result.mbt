///|
fn capture_to_json(capture : Capture) -> Json {
  {
    "name": Json::string(capture.name),
    "events": Json::array(capture.events.map(event_to_json)),
  }
}

///|
/// Identity is scoped to the same session and successful input occurrence order.
/// Length prefixes prevent collisions caused by delimiters in user identifiers.
pub fn Match::identity(self : Match) -> String {
  let builder = StringBuilder()
  builder.write_string("\{self.pattern.length()}:\{self.pattern}\{self.key.length()}:\{self.key}:")
  for capture in self.captures {
    builder.write_string("\{capture.events.length()},")
  }
  builder.write_string(":")
  for ordinal in self.occurrences { builder.write_string("\{ordinal},") }
  builder.write_string(if self.absence { "absence" } else { "positive" })
  builder.to_string()
}

///|
pub fn match_to_json(value : Match) -> Json {
  {
    "pattern": Json::string(value.pattern),
    "key": Json::string(value.key),
    "identity": Json::string(value.identity()),
    "started": Json::string(value.started.to_string()),
    "ended": Json::string(value.ended.to_string()),
    "absence": Json::boolean(value.absence),
    "occurrences": Json::array(value.occurrences.map(n => Json::string(n.to_string()))),
    "captures": Json::array(value.captures.map(capture_to_json)),
  }
}

///|
pub fn timeout_to_json(value : Timeout) -> Json {
  {
    "pattern": Json::string(value.pattern),
    "key": Json::string(value.key),
    "deadline": Json::string(value.deadline.to_string()),
    "captures": Json::array(value.captures.map(capture_to_json)),
  }
}

///|
pub fn batch_to_json(batch : Batch) -> Json {
  {
    "schema_version": 1,
    "matches": Json::array(batch.matches.map(match_to_json)),
    "timeouts": Json::array(batch.timeouts.map(timeout_to_json)),
    "processed": Json::number(batch.processed.to_double()),
    "work": Json::number(batch.work.to_double()),
  }
}

///|
pub fn command_to_json(command : StreamInput) -> Json {
  match command {
    Observe(event) => { "type": "event", "event": event_to_json(event) }
    Advance(time) => { "type": "watermark", "time": Json::string(time.to_string()) }
  }
}

///|
pub fn command_from_json(value : Json) -> StreamInput raise CepError {
  let object = codec_object(value, "command")
  match codec_text_property(object, "type", "command") {
    "event" => {
      codec_keys(object, ["type", "event"], "command")
      Observe(event_from_json(codec_required(object, "event", "command")))
    }
    "watermark" => {
      codec_keys(object, ["type", "time"], "command")
      let time = codec_int64(codec_required(object, "time", "command"), "command.time")
      if time < 0L || time > 9007230790740991L {
        raise Invalid(path="command.time", reason="watermark outside supported domain")
      }
      Advance(time)
    }
    _ => raise Invalid(path="command.type", reason="expected event or watermark")
  }
}

///|
pub fn parse_command(text : String) -> StreamInput raise CepError {
  command_from_json(codec_parse(text))
}

///|
pub fn format_command(command : StreamInput) -> String raise CepError {
  codec_bounded_format(command_to_json(command))
}
