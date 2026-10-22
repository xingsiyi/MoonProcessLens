///|
fn selection_pattern(
  policy : AfterMatch,
  trailing_absence~ : Bool = false,
) -> Pattern raise CepError {
  let stages = [
    Stage::new("a", Kind("a")),
    Stage::new("b", Kind("b"), contiguity=SkipAny),
  ]
  if trailing_absence {
    Pattern::new("selection", stages, 10L, after_match=policy, absence=Kind("cancel"))
  } else {
    Pattern::new("selection", stages, 10L, after_match=policy)
  }
}

///|
fn selection_input(engine : Engine, key~ : String = "k") -> Unit raise CepError {
  for (id, kind, time) in [
    ("a1", "a", 0L),
    ("a2", "a", 1L),
    ("b1", "b", 2L),
    ("b2", "b", 3L),
  ] {
    ignore(engine.push(Event::new(id, key, time, kind)))
  }
}

///|
fn selection_signature(value : Match) -> String {
  let text = StringBuilder()
  text.write_string("\{value.key()}:")
  for capture in value.captures() {
    text.write_string("\{capture.name}=")
    for event in capture.events {
      text.write_string("\{event.id()},")
    }
    text.write_string(";")
  }
  text.to_string()
}

///|
test "positive after-match policies select across shared starts" {
  for (policy, expected) in [
    (NoSkip, 4),
    (SkipToNextStart, 2),
    (SkipPastLast, 1),
  ] {
    let engine = Engine::new([selection_pattern(policy)])
    selection_input(engine)
    let matches = engine.advance_watermark(3L).matches()
    assert_eq(matches.length(), expected)
    assert_eq(matches[0].events("a")[0].id(), "a1")
    assert_eq(matches[0].events("b")[0].id(), "b1")
  }
}

///|
test "absence completion applies after-match policies before every emission" {
  for (policy, expected) in [
    (NoSkip, 4),
    (SkipToNextStart, 2),
    (SkipPastLast, 1),
  ] {
    let engine = Engine::new([selection_pattern(policy, trailing_absence=true)])
    selection_input(engine)
    let matches = engine.advance_watermark(11L).matches()
    assert_eq(matches.length(), expected)
    assert_true(matches[0].is_absence())
    assert_eq(matches[0].events("a")[0].id(), "a1")
    assert_eq(matches[0].events("b")[0].id(), "b1")
  }
}

///|
test "absence selection does not depend on watermark batching" {
  for policy in [NoSkip, SkipToNextStart, SkipPastLast] {
    let together = Engine::new([selection_pattern(policy, trailing_absence=true)])
    let split = Engine::new([selection_pattern(policy, trailing_absence=true)])
    selection_input(together)
    selection_input(split)
    let expected = together.advance_watermark(11L).matches().map(selection_signature)
    let actual = split.advance_watermark(10L).matches().map(selection_signature)
    for value in split.advance_watermark(11L).matches() {
      actual.push(selection_signature(value))
    }
    assert_eq(actual, expected)
  }
}

///|
test "after-match selection is isolated by entity key" {
  for (policy, expected) in [(NoSkip, 8), (SkipToNextStart, 4), (SkipPastLast, 2)] {
    let engine = Engine::new([selection_pattern(policy)])
    selection_input(engine, key="left")
    selection_input(engine, key="right")
    let matches = engine.advance_watermark(3L).matches()
    assert_eq(matches.length(), expected)
    assert_eq(matches.filter(value => value.key() == "left").length(), expected / 2)
    assert_eq(matches.filter(value => value.key() == "right").length(), expected / 2)
  }
}

///|
test "after-match selection respects event-time order over arrival ordinals" {
  for (policy, expected) in [(NoSkip, 4), (SkipToNextStart, 2), (SkipPastLast, 1)] {
    let engine = Engine::new([selection_pattern(policy)])
    for (id, kind, time) in [
      ("b2", "b", 3L),
      ("a2", "a", 1L),
      ("b1", "b", 2L),
      ("a1", "a", 0L),
    ] {
      ignore(engine.push(Event::new(id, "k", time, kind)))
    }
    let matches = engine.advance_watermark(3L).matches()
    assert_eq(matches.length(), expected)
    assert_eq(matches[0].events("a")[0].id(), "a1")
    assert_eq(matches[0].events("b")[0].id(), "b1")
    assert_eq(matches[0].occurrences(), [4L, 3L])
  }
}

///|
test "equal-time events use occurrence order for skip-past-last" {
  for (policy, expected) in [(NoSkip, 4), (SkipToNextStart, 2), (SkipPastLast, 1)] {
    let engine = Engine::new([selection_pattern(policy)])
    for (id, kind) in [("a1", "a"), ("a2", "a"), ("b1", "b"), ("b2", "b")] {
      ignore(engine.push(Event::new(id, "k", 0L, kind)))
    }
    let matches = engine.advance_watermark(0L).matches()
    assert_eq(matches.length(), expected)
    assert_eq(matches[0].occurrences(), [1L, 3L])
  }
}

///|
test "after-match selection handles repeated-stage competing captures" {
  for (policy, expected) in [(NoSkip, 3), (SkipToNextStart, 2), (SkipPastLast, 1)] {
    let pattern = Pattern::new("repeat", [
      Stage::new("a", Kind("a"), min=1, max=2),
      Stage::new("b", Kind("b"), contiguity=SkipAny),
    ], 10L, after_match=policy)
    let engine = Engine::new([pattern])
    for (id, kind, time) in [("a1", "a", 0L), ("a2", "a", 1L), ("b1", "b", 2L)] {
      ignore(engine.push(Event::new(id, "k", time, kind)))
    }
    assert_eq(engine.advance_watermark(2L).matches().length(), expected)
  }
}

///|
test "stage guards cancel before positive acceptance by explicit precedence" {
  let pattern = Pattern::new("guard-precedence", [
    Stage::new("a", Kind("a")),
    Stage::new("b", Kind("b"), forbidden=Kind("b")),
  ], 10L)
  let engine = Engine::new([pattern])
  ignore(engine.push(Event::new("a", "k", 0L, "a")))
  ignore(engine.push(Event::new("b", "k", 1L, "b")))
  let batch = engine.advance_watermark(10L)
  assert_eq(batch.matches().length(), 0)
  assert_eq(batch.timeouts().length(), 0)
}

///|
test "stage guards are partition scoped and observe skipped events" {
  let pattern = Pattern::new("guard-scope", [
    Stage::new("a", Kind("a")),
    Stage::new("b", Kind("b"), forbidden=Kind("cancel")),
  ], 10L)
  let engine = Engine::new([pattern])
  ignore(engine.push(Event::new("a", "left", 0L, "a")))
  ignore(engine.push(Event::new("other-cancel", "right", 1L, "cancel")))
  ignore(engine.push(Event::new("b", "left", 2L, "b")))
  assert_eq(engine.advance_watermark(2L).matches().length(), 1)
  let cancelled = Engine::new([pattern])
  ignore(cancelled.push(Event::new("a", "left", 0L, "a")))
  ignore(cancelled.push(Event::new("cancel", "left", 1L, "cancel")))
  ignore(cancelled.push(Event::new("b", "left", 2L, "b")))
  assert_eq(cancelled.advance_watermark(10L).matches().length(), 0)
}

///|
test "trailing absence observes all same-time occurrences through deadline" {
  for cancelled in [false, true] {
    let engine = Engine::new([selection_pattern(NoSkip, trailing_absence=true)])
    ignore(engine.push(Event::new("a", "k", 0L, "a")))
    ignore(engine.push(Event::new("b", "k", 1L, "b")))
    if cancelled {
      ignore(engine.push(Event::new("cancel", "k", 10L, "cancel")))
    } else {
      ignore(engine.push(Event::new("cancel", "other", 10L, "cancel")))
    }
    let batch = engine.advance_watermark(10L)
    assert_eq(batch.matches().length(), if cancelled { 0 } else { 1 })
  }
}

///|
test "output budget counts selected outputs rather than discarded candidates" {
  for trailing_absence in [false, true] {
    let engine = Engine::new(
      [selection_pattern(SkipPastLast, trailing_absence~)],
      limits={ ..Limits::default(), outputs_per_call: 1 },
    )
    for (id, kind, time) in [("a1", "a", 0L), ("a2", "a", 1L), ("b1", "b", 2L)] {
      ignore(engine.push(Event::new(id, "k", time, kind)))
    }
    let batch = engine.advance_watermark(if trailing_absence { 11L } else { 2L })
    assert_eq(batch.matches().length(), 1)
    assert_eq(batch.timeouts().length(), 0)
  }
}
