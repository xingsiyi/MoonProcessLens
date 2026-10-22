///|
fn integration_pattern() -> Pattern raise CepError {
  Pattern::new("sequence", [
    Stage::new("a", Kind("a")),
    Stage::new("b", Kind("b")),
  ], 10L)
}

///|
test "push_many accepts every input in order including an empty batch" {
  let engine = Engine::new([integration_pattern()])
  assert_eq(engine.push_many([]), [])
  let a = Event::new("a", "k", 0L, "a")
  let b = Event::new("b", "k", 1L, "b")
  assert_eq(engine.push_many([a, b]), [1L, 2L])
  let batch = engine.advance_watermark(1L)
  assert_eq(batch.processed(), 2)
  assert_eq(batch.matches().length(), 1)
  assert_eq(batch.matches()[0].occurrences(), [1L, 2L])
}

///|
test "push_many late failure preserves prior state and occurrence counter" {
  let engine = Engine::new([integration_pattern()])
  ignore(engine.push(Event::new("a", "k", 0L, "a")))
  ignore(engine.advance_watermark(0L))
  let buffered = engine.buffered()
  let active = engine.active_states()
  assert_true(try {
    ignore(engine.push_many([
      Event::new("next", "k", 2L, "b"),
      Event::new("late", "k", 0L, "b"),
    ]))
    false
  } catch {
    LateEvent(..) => true
    _ => false
  })
  assert_eq(engine.watermark(), 0L)
  assert_eq(engine.buffered(), buffered)
  assert_eq(engine.active_states(), active)
  assert_eq(engine.push(Event::new("actual", "k", 1L, "b")), 2L)
  let result = engine.advance_watermark(2L)
  assert_eq(result.processed(), 1)
  assert_eq(result.matches()[0].events("b")[0].id(), "actual")
}

///|
test "push_many buffer exhaustion does not retain a successful prefix" {
  let engine = Engine::new([integration_pattern()], limits={
    ..Limits::default(),
    buffered_events: 1,
  })
  assert_true(try {
    ignore(engine.push_many([
      Event::new("a", "k", 0L, "a"),
      Event::new("b", "k", 1L, "b"),
    ]))
    false
  } catch {
    Resource(..) => true
    _ => false
  })
  assert_eq(engine.buffered(), 0)
  assert_eq(engine.watermark(), -1L)
  assert_eq(engine.push(Event::new("retry", "k", 0L, "a")), 1L)
}

///|
test "forked engines advance independently with separate event buffers" {
  let source = Engine::new([integration_pattern()])
  ignore(source.push(Event::new("a", "k", 0L, "a")))
  ignore(source.advance_watermark(0L))
  ignore(source.push(Event::new("buffered", "other", 3L, "b")))
  let forked = source.fork()
  ignore(forked.push(Event::new("forked-b", "k", 1L, "b")))
  let fork_batch = forked.advance_watermark(3L)
  assert_eq(fork_batch.matches().length(), 1)
  assert_eq(source.watermark(), 0L)
  assert_eq(source.buffered(), 1)
  assert_eq(source.active_states(), 1)
  ignore(source.push(Event::new("source-b", "k", 2L, "b")))
  let source_batch = source.advance_watermark(3L)
  assert_eq(source_batch.matches()[0].events("b")[0].id(), "source-b")
  assert_eq(fork_batch.matches()[0].events("b")[0].id(), "forked-b")
}

///|
test "fork deep copies internal capture arrays fields and condition arrays" {
  let condition = All([Kind("a"), Has("value")])
  let pattern = Pattern::new("owned", [
    Stage::new("a", condition),
    Stage::new("b", Kind("b")),
  ], 10L)
  let source = Engine::new([pattern])
  ignore(source.push(Event::new("a", "k", 0L, "a", fields=[
    { name: "value", value: Integer(1L) },
  ])))
  ignore(source.advance_watermark(0L))
  ignore(source.push(Event::new("waiting", "other", 3L, "a", fields=[
    { name: "value", value: Integer(2L) },
  ])))
  let forked = source.fork()
  // White-box mutation checks deeper ownership than the public API exposes.
  forked.active[0].captures[0].events[0].fields.clear()
  forked.active[0].positions.clear()
  forked.buffer[0].event.fields.clear()
  match forked.patterns[0].stages[0].condition {
    All(children) => children.clear()
    _ => fail("expected condition child array")
  }
  assert_eq(source.active[0].captures[0].events[0].field("value"), Some(Integer(1L)))
  assert_eq(source.active[0].positions, [1L])
  assert_eq(source.buffer[0].event.field("value"), Some(Integer(2L)))
  assert_true(!source.patterns[0].stages[0].condition.evaluate(
    Event::new("no-field", "k", 4L, "a"), [],
  ))
}

///|
test "checkpoint restores are repeatable and detached from later progress" {
  let engine = Engine::new([integration_pattern()])
  ignore(engine.push(Event::new("a", "k", 0L, "a")))
  ignore(engine.advance_watermark(0L))
  let checkpoint = engine.checkpoint()
  assert_eq(checkpoint.watermark(), 0L)
  assert_eq(checkpoint.buffered(), 0)
  assert_eq(checkpoint.active_states(), 1)
  ignore(engine.push(Event::new("later", "k", 1L, "b")))
  ignore(engine.advance_watermark(10L))
  let first = checkpoint.restore()
  let second = checkpoint.restore()
  ignore(first.push(Event::new("one", "k", 2L, "b")))
  ignore(second.push(Event::new("two", "k", 3L, "b")))
  assert_eq(first.advance_watermark(10L).matches()[0].events("b")[0].id(), "one")
  assert_eq(second.advance_watermark(10L).matches()[0].events("b")[0].id(), "two")
  assert_eq(checkpoint.restore().watermark(), 0L)
}

///|
test "replay preserves explicit command order and does not flush implicitly" {
  let pattern = integration_pattern()
  let commands = [
    Observe(Event::new("b", "k", 1L, "b")),
    Observe(Event::new("a", "k", 0L, "a")),
    Advance(1L),
    Advance(10L),
  ]
  let first = replay([pattern], commands)
  let second = replay([pattern], commands)
  assert_eq(first.length(), 2)
  assert_eq(second.length(), 2)
  assert_eq(first[0].matches()[0].occurrences(), [2L, 1L])
  assert_eq(first[0].matches()[0].occurrences(), second[0].matches()[0].occurrences())
  assert_eq(first[0].processed(), second[0].processed())
  assert_eq(first[1].matches().length(), 0)
  assert_eq(replay([pattern], [Observe(Event::new("a", "k", 0L, "a"))]).length(), 0)
}

///|
test "replay bounds aggregate output and commands with per-advance work" {
  let pattern = Pattern::new("single", [Stage::new("a", Kind("a"))], 10L)
  let commands = [
    Observe(Event::new("one", "k", 0L, "a")),
    Advance(0L),
    Observe(Event::new("two", "k", 1L, "a")),
    Advance(1L),
  ]
  assert_true(try {
    ignore(replay([pattern], commands, limits={
      ..Limits::default(), outputs_per_call: 1,
    }, max_outputs=1))
    false
  } catch {
    Resource(resource~, ..) => resource == "replay outputs"
    _ => false
  })
  assert_eq(
    replay([pattern], [Advance(0L), Advance(0L), Advance(0L)], limits={
      ..Limits::default(), work_per_call: 2,
    }).length(),
    3,
  )
  assert_true(try {
    ignore(replay([pattern], commands, max_commands=3))
    false
  } catch {
    Resource(..) => true
    _ => false
  })
}

///|
test "larger budgets retry a failed advance from a detached copy or checkpoint" {
  let pattern = Pattern::new("single", [Stage::new("a", Kind("a"))], 10L)
  let engine = Engine::new([pattern], limits={
    ..Limits::default(), outputs_per_call: 1,
  })
  ignore(engine.push_many([
    Event::new("one", "k", 0L, "a"),
    Event::new("two", "k", 0L, "a"),
  ]))
  assert_true(try { ignore(engine.advance_watermark(0L)); false } catch { _ => true })
  let checkpoint = engine.checkpoint()
  let raised = { ..engine.limits(), outputs_per_call: 2 }
  let retry = engine.with_limits(raised)
  assert_eq(retry.advance_watermark(0L).matches().length(), 2)
  assert_eq(checkpoint.restore_with_limits(raised).advance_watermark(0L).matches().length(), 2)
  assert_eq(engine.watermark(), -1L)
  assert_eq(engine.buffered(), 2)
  assert_eq(engine.limits().outputs_per_call, 1)
}

///|
test "replacement budgets must accommodate buffered events and active keys" {
  let engine = Engine::new([integration_pattern()])
  ignore(engine.push_many([
    Event::new("one", "k1", 0L, "a"),
    Event::new("two", "k2", 0L, "a"),
  ]))
  assert_true(try {
    ignore(engine.with_limits({ ..Limits::default(), buffered_events: 1 }))
    false
  } catch { Resource(..) => true; _ => false })
  ignore(engine.advance_watermark(0L))
  assert_eq(engine.active_states(), 2)
  assert_true(try {
    ignore(engine.with_limits({ ..Limits::default(), active_states: 1 }))
    false
  } catch { Resource(..) => true; _ => false })
  assert_true(try {
    ignore(engine.with_limits({ ..Limits::default(), partitions: 1 }))
    false
  } catch { Resource(..) => true; _ => false })
  assert_eq(engine.active_states(), 2)
  assert_eq(engine.watermark(), 0L)
}
