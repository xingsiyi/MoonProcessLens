///|
test "state explosion errors preserve input and permit a larger-budget retry" {
  let pattern = Pattern::new(
    "bounded-branching",
    [
      Stage::new("a", Kind("a"), min=1, max=3, contiguity=SkipAny),
      Stage::new("b", Kind("b"), contiguity=SkipAny),
    ],
    10L,
  )
  let engine = Engine::new([pattern], limits={
    ..Limits::default(),
    active_states: 2,
  })
  ignore(
    engine.push_many([
      Event::new("a1", "k", 0L, "a"),
      Event::new("a2", "k", 1L, "a"),
      Event::new("b1", "k", 2L, "b"),
    ]),
  )
  assert_true(
    try {
      ignore(engine.advance_watermark(2L))
      false
    } catch {
      Resource(..) => true
      _ => false
    },
  )
  assert_eq(engine.buffered(), 3)
  assert_eq(engine.active_states(), 0)
  assert_eq(engine.watermark(), -1L)
  let retried = engine.with_limits({ ..Limits::default(), active_states: 64, })
  assert_eq(retried.advance_watermark(2L).matches().length(), 3)
  assert_eq(engine.inspect().occurrence(), 3L)
}

///|
test "engine work budget aborts an advance before any partial commit" {
  let engine = Engine::new([pair_pattern()], limits={
    ..Limits::default(),
    work_per_call: 1,
  })
  input(engine, "a", 0L)
  assert_true(
    try {
      ignore(engine.advance_watermark(0L))
      false
    } catch {
      Resource(..) => true
      _ => false
    },
  )
  assert_eq(engine.buffered(), 1)
  assert_eq(engine.watermark(), -1L)
  let retry = engine.with_limits(Limits::default())
  ignore(retry.advance_watermark(0L))
  assert_eq(retry.active_states(), 1)
}
