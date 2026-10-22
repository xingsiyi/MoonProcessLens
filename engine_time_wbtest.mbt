///|
fn time_pair_pattern(within : Int64) -> Pattern raise CepError {
  Pattern::new("time-boundary", [
    Stage::new("a", Kind("a")),
    Stage::new("b", Kind("b")),
  ], within)
}

///|
test "maximum event time still has a reachable positive timeout" {
  let engine = Engine::new([time_pair_pattern(10L)])
  ignore(engine.push(Event::new("last-a", "k", 9007199254740991L, "a")))
  let open = engine.advance_watermark(9007199254740991L)
  assert_eq(open.matches().length(), 0)
  assert_eq(open.timeouts().length(), 0)
  assert_eq(engine.active_states(), 1)
  let expired = engine.advance_watermark(9007199254741001L)
  assert_eq(expired.timeouts().length(), 1)
  assert_eq(expired.timeouts()[0].deadline(), 9007199254741001L)
  assert_eq(engine.active_states(), 0)
}

///|
test "finish reaches maximum absence deadline without overflowing" {
  let pattern = Pattern::new("maximum-absence", [
    Stage::new("a", Kind("a")),
  ], 31536000000L, absence=Kind("cancel"))
  let engine = Engine::new([pattern])
  ignore(engine.push(Event::new("last-a", "k", 9007199254740991L, "a")))
  let batch = engine.finish()
  assert_eq(batch.processed(), 1)
  assert_eq(batch.matches().length(), 1)
  assert_eq(batch.matches()[0].ended(), 9007230790740991L)
  assert_eq(batch.matches()[0].events("a")[0].time(), 9007199254740991L)
  assert_true(batch.matches()[0].is_absence())
  assert_eq(batch.timeouts().length(), 0)
  assert_eq(engine.watermark(), 9007230790740991L)
  assert_eq(engine.buffered(), 0)
  assert_eq(engine.active_states(), 0)
}

///|
test "finish on an empty engine is a valid idempotent terminal watermark" {
  let engine = Engine::new([time_pair_pattern(10L)])
  for _ in 0..<2 {
    let batch = engine.finish()
    assert_eq(batch.processed(), 0)
    assert_eq(batch.matches().length(), 0)
    assert_eq(batch.timeouts().length(), 0)
    assert_eq(engine.buffered(), 0)
    assert_eq(engine.active_states(), 0)
    assert_eq(engine.watermark(), 9007230790740991L)
  }
}

///|
test "finish flushes buffered events and a repeated finish emits nothing" {
  let engine = Engine::new([time_pair_pattern(10L)])
  ignore(engine.push(Event::new("b", "k", 2L, "b")))
  ignore(engine.push(Event::new("a", "k", 1L, "a")))
  let batch = engine.finish()
  assert_eq(batch.processed(), 2)
  assert_eq(batch.matches().length(), 1)
  assert_eq(batch.matches()[0].events("a")[0].id(), "a")
  assert_eq(batch.matches()[0].events("b")[0].id(), "b")
  let repeated = engine.finish()
  assert_eq(repeated.processed(), 0)
  assert_eq(repeated.matches().length(), 0)
  assert_eq(repeated.timeouts().length(), 0)
}

///|
test "push after finish is late and cannot reopen the stream" {
  let engine = Engine::new([time_pair_pattern(10L)])
  ignore(engine.finish())
  assert_true(
    try {
      ignore(engine.push(Event::new("too-late", "k", 9007199254740991L, "a")))
      false
    } catch {
      LateEvent(..) => true
      _ => false
    },
  )
  assert_eq(engine.buffered(), 0)
  assert_eq(engine.watermark(), 9007230790740991L)
  assert_true(
    try {
      ignore(engine.advance_watermark(9007199254740991L))
      false
    } catch {
      WatermarkRegression(..) => true
      _ => false
    },
  )
}

///|
test "watermark maximum is inclusive and one beyond is rejected atomically" {
  let engine = Engine::new([time_pair_pattern(1L)])
  ignore(engine.advance_watermark(9007230790740991L))
  assert_true(
    try {
      ignore(engine.advance_watermark(9007230790740992L))
      false
    } catch {
      Invalid(..) => true
      _ => false
    },
  )
  assert_eq(engine.watermark(), 9007230790740991L)
}

///|
test "positive completion at maximum event time wins before timeout" {
  let engine = Engine::new([time_pair_pattern(10L)])
  ignore(engine.push(Event::new("start", "k", 9007199254740981L, "a")))
  ignore(engine.push(Event::new("end", "k", 9007199254740991L, "b")))
  let batch = engine.finish()
  assert_eq(batch.matches().length(), 1)
  assert_eq(batch.matches()[0].ended(), 9007199254740991L)
  assert_eq(batch.timeouts().length(), 0)
}

///|
test "failed finish preserves pending events active state and watermark" {
  let engine = Engine::new(
    [time_pair_pattern(1L)],
    limits={ ..Limits::default(), outputs_per_call: 1 },
  )
  ignore(engine.push(Event::new("a1", "left", 0L, "a")))
  ignore(engine.push(Event::new("a2", "right", 2L, "a")))
  assert_true(
    try {
      ignore(engine.finish())
      false
    } catch {
      Resource(..) => true
      _ => false
    },
  )
  assert_eq(engine.watermark(), -1L)
  assert_eq(engine.buffered(), 2)
  assert_eq(engine.active_states(), 0)
  assert_eq(engine.advance_watermark(1L).timeouts().length(), 1)
  assert_eq(engine.finish().timeouts().length(), 1)
}
