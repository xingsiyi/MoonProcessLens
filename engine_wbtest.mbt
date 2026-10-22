///|
fn pair_pattern(mode~ : Contiguity = SkipNext) -> Pattern raise CepError {
  Pattern::new("ab", [Stage::new("a", Kind("a")), Stage::new("b", Kind("b"), contiguity=mode)], 10L)
}

///|
fn input(engine : Engine, kind : String, time : Int64, key~ : String = "k") -> Unit raise CepError {
  let _ = engine.push(Event::new("\{kind}\{time}", key, time, kind))
}

///|
test "watermark sorts input and isolates entity keys" {
  let engine = Engine::new([pair_pattern()])
  input(engine, "b", 3L)
  input(engine, "a", 1L)
  input(engine, "b", 2L, key="other")
  assert_eq(engine.advance_watermark(0L).matches().length(), 0)
  let batch = engine.advance_watermark(3L)
  assert_eq(batch.processed(), 3)
  assert_eq(batch.matches().length(), 1)
  let m = batch.matches()[0]
  assert_eq(m.events("a")[0].time(), 1L)
  assert_eq(m.events("b")[0].time(), 3L)
  assert_eq(m.occurrences(), [2L, 1L])
  assert_true(try { input(engine, "a", 3L); false } catch { LateEvent(..) => true; _ => false })
}

///|
test "strict contiguity observes unrelated events of the same entity" {
  let engine = Engine::new([pair_pattern(mode=Strict)])
  input(engine, "a", 0L)
  input(engine, "x", 1L)
  input(engine, "b", 2L)
  assert_eq(engine.advance_watermark(2L).matches().length(), 0)
}

///|
test "skip-next consumes first matching next event while skip-any branches" {
  for (mode, expected) in [(SkipNext, 1), (SkipAny, 2)] {
    let engine = Engine::new([pair_pattern(mode~)])
    input(engine, "a", 0L)
    input(engine, "b", 1L)
    input(engine, "b", 2L)
    assert_eq(engine.advance_watermark(2L).matches().length(), expected)
  }
}

///|
test "positive sequence may complete at exact window deadline" {
  let engine = Engine::new([pair_pattern()])
  input(engine, "a", 0L)
  input(engine, "b", 10L)
  assert_eq(engine.advance_watermark(10L).matches().length(), 1)
  let other = Engine::new([pair_pattern()])
  input(other, "a", 0L)
  input(other, "b", 11L)
  let batch = other.advance_watermark(11L)
  assert_eq(batch.matches().length(), 0)
  assert_eq(batch.timeouts().length(), 1)
}

///|
test "budget failure rolls back popped input and watermark" {
  let pattern = Pattern::new("one", [Stage::new("a", Kind("a"))], 10L)
  let engine = Engine::new([pattern], limits={ ..Limits::default(), outputs_per_call: 1 })
  input(engine, "a", 1L)
  input(engine, "a", 2L)
  assert_true(try { let _ = engine.advance_watermark(2L); false } catch { Resource(..) => true; _ => false })
  assert_eq(engine.watermark(), -1L)
  assert_eq(engine.buffered(), 2)
  assert_eq(engine.advance_watermark(1L).matches().length(), 1)
  assert_eq(engine.advance_watermark(2L).matches().length(), 1)
}
