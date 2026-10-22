///|
test "persisted session restores active branches and buffered input" {
  let session = Session::new([pair_pattern()])
  ignore(session.apply(Observe(Event::new("a", "k", 0L, "a"))))
  ignore(session.apply(Advance(0L)))
  ignore(session.apply(Observe(Event::new("b", "k", 1L, "b"))))
  let restored = parse_session(format_session(session))
  assert_eq(restored.active_states(), 1)
  assert_eq(restored.buffered(), 1)
  assert_eq(batch_to_json(restored.finish()), batch_to_json(session.finish()))
}

///|
test "restore rejects corruption future versions and total replay work excess" {
  let session = Session::new([pair_pattern()])
  ignore(session.apply(Observe(Event::new("a", "k", 0L, "a"))))
  ignore(session.apply(Advance(0L)))
  assert_true(
    try {
      ignore(parse_session(format_session(session), max_work=1))
      false
    } catch {
      Resource(..) => true
      _ => false
    },
  )
  let wire = session_to_json(session)
  let object = codec_object(wire, "test")
  object.set("schema_version", Json::number(2.0))
  assert_true(
    try {
      ignore(session_from_json(wire))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(session.watermark(), 0L)
}
