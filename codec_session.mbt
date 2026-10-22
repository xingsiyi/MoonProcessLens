///|
pub fn limits_to_json(limits : Limits) -> Json {
  {
    "buffered_events": Json::number(limits.buffered_events.to_double()),
    "active_states": Json::number(limits.active_states.to_double()),
    "partitions": Json::number(limits.partitions.to_double()),
    "outputs_per_call": Json::number(limits.outputs_per_call.to_double()),
    "work_per_call": Json::number(limits.work_per_call.to_double()),
  }
}

///|
pub fn limits_from_json(value : Json) -> Limits raise CepError {
  let object = codec_object(value, "limits")
  codec_keys(object, ["buffered_events", "active_states", "partitions", "outputs_per_call", "work_per_call"], "limits")
  let limits : Limits = {
    buffered_events: codec_int32(codec_required(object, "buffered_events", "limits"), "limits.buffered_events"),
    active_states: codec_int32(codec_required(object, "active_states", "limits"), "limits.active_states"),
    partitions: codec_int32(codec_required(object, "partitions", "limits"), "limits.partitions"),
    outputs_per_call: codec_int32(codec_required(object, "outputs_per_call", "limits"), "limits.outputs_per_call"),
    work_per_call: codec_int32(codec_required(object, "work_per_call", "limits"), "limits.work_per_call"),
  }
  limits.validate()
  limits
}

///|
pub fn session_to_json(session : Session) -> Json {
  {
    "schema_version": 1,
    "patterns": Json::array(session.engine.patterns.map(pattern_to_json)),
    "limits": limits_to_json(session.engine.limits),
    "max_commands": Json::number(session.max_commands.to_double()),
    "commands": Json::array(session.commands.map(command_to_json)),
  }
}

///|
/// Restore by validating and replaying committed inputs. max_work is a total
/// import budget, in addition to each engine advance's own work limit.
pub fn session_from_json(
  value : Json,
  max_work~ : Int = 10000000,
) -> Session raise CepError {
  if max_work < 1 || max_work > 100000000 {
    raise Invalid(path="restore.max_work", reason="expected 1..100000000")
  }
  let object = codec_object(value, "session")
  codec_keys(object, ["schema_version", "patterns", "limits", "max_commands", "commands"], "session")
  if codec_int32(codec_required(object, "schema_version", "session"), "session.schema_version") != 1 {
    raise Invalid(path="session.schema_version", reason="only version 1 is supported")
  }
  let limits = limits_from_json(codec_required(object, "limits", "session"))
  let max_commands = codec_int32(codec_required(object, "max_commands", "session"), "session.max_commands")
  let patterns_json = codec_array(codec_required(object, "patterns", "session"), "session.patterns")
  if patterns_json.length() > 64 { raise Resource(resource="patterns", limit=64) }
  let patterns = patterns_json.map(pattern_from_json)
  let session = Session::new(patterns, limits~, max_commands~)
  let commands = codec_array(codec_required(object, "commands", "session"), "session.commands")
  if commands.length() > max_commands { raise Resource(resource="journal commands", limit=max_commands) }
  let work = Work::{ used: 0, limit: max_work }
  for item in commands {
    work.charge()
    let command = command_from_json(item)
    match session.apply(command) {
      Accepted(_) => ()
      Progress(batch) => work.charge(amount=batch.work)
    }
  }
  session
}

///|
pub fn format_session(session : Session) -> String raise CepError {
  codec_bounded_format(session_to_json(session))
}

///|
pub fn parse_session(text : String, max_work~ : Int = 10000000) -> Session raise CepError {
  session_from_json(codec_parse(text, max_depth=128), max_work~)
}
