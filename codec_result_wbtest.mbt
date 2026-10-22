///|
test "match identities distinguish capture assignments and key delimiters" {
  let engine = Engine::new([pair_pattern()])
  input(engine, "a", 0L)
  input(engine, "b", 1L)
  let batch = engine.advance_watermark(1L)
  let m = batch.matches()[0]
  let replayed = replay([pair_pattern()], [
    Observe(Event::new("a0", "k", 0L, "a")),
    Observe(Event::new("b1", "k", 1L, "b")),
    Advance(1L),
  ])
  assert_eq(m.identity(), replayed[0].matches()[0].identity())
  assert_true(m.identity() != { ..m, key: "k:", }.identity())
  assert_true(m.identity() != { ..m, absence: true, }.identity())
  assert_eq(
    codec_int32(
      codec_required(codec_object(batch_to_json(batch), "b"), "processed", "b"),
      "n",
    ),
    2,
  )
}

///|
test "command interchange preserves event data and terminal watermark" {
  let event = Event::new("e", "k", 0L, "a", fields=[
    { name: "n", value: Integer(-9223372036854775808L), },
  ])
  for command in [Observe(event), Advance(9007230790740991L)] {
    assert_eq(parse_command(format_command(command)), command)
  }
  assert_true(
    try {
      ignore(parse_command("{\"type\":\"watermark\",\"time\":\"-1\"}"))
      false
    } catch {
      _ => true
    },
  )
}
