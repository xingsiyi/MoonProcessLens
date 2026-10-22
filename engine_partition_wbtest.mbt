///|
test "expired keys release partition quota before a later key starts" {
  let engine = Engine::new([pair_pattern()], limits={
    ..Limits::default(),
    partitions: 1,
  })
  input(engine, "a", 0L, key="old")
  input(engine, "a", 11L, key="new")
  let batch = engine.advance_watermark(11L)
  assert_eq(batch.timeouts().length(), 1)
  assert_eq(batch.timeouts()[0].key(), "old")
  assert_eq(engine.active_states(), 1)
}

///|
test "new keys at exact deadline retain old key until its timestamp closes" {
  let engine = Engine::new([pair_pattern()], limits={
    ..Limits::default(),
    partitions: 1,
  })
  input(engine, "a", 0L, key="old")
  input(engine, "a", 10L, key="new")
  assert_true(
    try {
      ignore(engine.advance_watermark(10L))
      false
    } catch {
      Resource(..) => true
      _ => false
    },
  )
  assert_eq(engine.buffered(), 2)
}

///|
test "many independent keys avoid scanning all states on every event" {
  let engine = Engine::new([pair_pattern()], limits={
    ..Limits::default(),
    work_per_call: 20000,
  })
  for i in 0..<500 {
    input(engine, "a", 0L, key="k\{i}")
  }
  for i in 0..<500 {
    input(engine, "b", 1L, key="k\{i}")
  }
  let batch = engine.advance_watermark(1L)
  assert_eq(batch.matches().length(), 500)
  assert_true(batch.work() < 20000)
  assert_eq(engine.active_states(), 0)
}
