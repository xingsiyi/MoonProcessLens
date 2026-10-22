///|
test "stage defaults and bounded occurrence inspection" {
  let stage = Stage::new("first", Always)
  assert_eq(stage.name(), "first")
  assert_eq(stage.minimum(), 1)
  assert_eq(stage.maximum(), 1)
  assert_eq(stage.contiguity(), SkipNext)
  assert_true(stage.forbidden() is None)
  assert_true(!stage.is_optional())
  assert_true(!stage.is_repeated())
  let optional = Stage::new("optional", Always, min=0, max=32)
  assert_true(optional.is_optional())
  assert_true(optional.is_repeated())
}

///|
test "stage occurrence limits reject invalid combinations" {
  for pair in [(-1, 1), (0, 0), (1, 0), (3, 2), (1, 33)] {
    let result = Some(
      Stage::new("stage", Always, min=pair.0, max=pair.1),
    ) catch {
      _ => None
    }
    assert_true(result is None)
  }
  assert_true(
    (Some(Stage::new("", Always)) catch { _ => None }) is None,
  )
}

///|
test "pattern defaults and detached stage lookups" {
  let stages = [Stage::new("first", Always), Stage::new("last", Always)]
  let pattern = Pattern::new("sequence", stages, 10L)
  stages.clear()
  assert_eq(pattern.id(), "sequence")
  assert_eq(pattern.within(), 10L)
  assert_eq(pattern.after_match(), NoSkip)
  assert_true(pattern.absence() is None)
  assert_eq(pattern.stage_names(), ["first", "last"])
  assert_eq(pattern.stage("last").unwrap().name(), "last")
  assert_true(pattern.stage("unknown") is None)
  assert_true(pattern.stage_at(-1) is None)
  assert_true(pattern.stage_at(2) is None)
  assert_eq(pattern.stage_at(0).unwrap().name(), "first")
  let returned = pattern.stages()
  returned.clear()
  assert_eq(pattern.stages().length(), 2)
}

///|
test "pattern rejects empty stages optional first and repeated names" {
  assert_true(
    (Some(Pattern::new("empty", [], 10L)) catch { _ => None }) is None,
  )
  assert_true(
    (Some(
      Pattern::new("optional-first", [
        Stage::new("first", Always, min=0),
      ], 10L),
    ) catch {
      _ => None
    })
    is None,
  )
  assert_true(
    (Some(
      Pattern::new("duplicate", [
        Stage::new("same", Always),
        Stage::new("same", Always),
      ], 10L),
    ) catch {
      _ => None
    })
    is None,
  )
}

///|
test "pattern window bounds are inclusive and reject out of range" {
  let stages = [Stage::new("first", Always)]
  assert_eq(Pattern::new("minimum", stages, 1L).within(), 1L)
  assert_eq(
    Pattern::new("maximum", stages, 31536000000L).within(),
    31536000000L,
  )
  for within in [-1L, 0L, 31536000001L] {
    assert_true(
      (Some(Pattern::new("invalid", stages, within)) catch { _ => None })
      is None,
    )
  }
  assert_true(
    (Some(Pattern::new("", stages, 10L)) catch { _ => None }) is None,
  )
}

///|
test "pattern exact stage limit is accepted and one more is rejected" {
  let stages : Array[Stage] = []
  for index in 0..<32 {
    stages.push(Stage::new("stage-\{index}", Always))
  }
  let pattern = Pattern::new("exact", stages, 10L)
  assert_eq(pattern.stages().length(), 32)
  stages.push(Stage::new("overflow", Always))
  assert_true(
    (Some(Pattern::new("too-many", stages, 10L)) catch { _ => None })
    is None,
  )
}

///|
test "pattern exact aggregate capture limit is enforced" {
  let stages : Array[Stage] = []
  for index in 0..<4 {
    stages.push(Stage::new("stage-\{index}", Always, min=32, max=32))
  }
  let exact = Pattern::new("exact", stages, 10L)
  assert_eq(exact.analysis().maximum_captures, 128)
  stages.push(Stage::new("overflow", Always))
  assert_true(
    (Some(Pattern::new("too-many", stages, 10L)) catch { _ => None })
    is None,
  )
}

///|
test "fixed sequence analysis counts captures and strict stages" {
  let pattern = Pattern::new("fixed", [
    Stage::new("first", Always),
    Stage::new("last", Always, contiguity=Strict),
  ], 10L, after_match=SkipPastLast)
  let analysis = pattern.analysis()
  assert_eq(analysis.minimum_captures, 2)
  assert_eq(analysis.maximum_captures, 2)
  assert_eq(analysis.nullable_stages, 0)
  assert_eq(analysis.variable_stages, 0)
  assert_eq(analysis.repeated_stages, 0)
  assert_eq(analysis.strict_stages, 1)
  assert_eq(analysis.skip_any_stages, 0)
  assert_eq(analysis.guarded_stages, 0)
  assert_true(!analysis.has_absence)
  assert_eq(analysis.branching_risk, FixedSequence)
  assert_eq(pattern.after_match(), SkipPastLast)
}

///|
test "analysis distinguishes repetition optionality and selection branches" {
  let repeated = Pattern::new("repeated", [
    Stage::new("first", Always, min=2, max=2),
  ], 10L)
  assert_eq(repeated.analysis().branching_risk, BoundedRepetition)
  assert_eq(repeated.analysis().minimum_captures, 2)
  let optional = Pattern::new("optional", [
    Stage::new("first", Always),
    Stage::new("maybe", Always, min=0, max=1),
  ], 10L)
  assert_eq(optional.analysis().nullable_stages, 1)
  assert_eq(optional.analysis().variable_stages, 1)
  assert_eq(optional.analysis().branching_risk, BoundedRepetition)
  let branching = Pattern::new("branching", [
    Stage::new("first", Always),
    Stage::new("last", Always, contiguity=SkipAny),
  ], 10L, after_match=SkipToNextStart)
  assert_eq(branching.analysis().skip_any_stages, 1)
  assert_eq(branching.analysis().branching_risk, CombinatorialSelection)
  assert_eq(branching.after_match(), SkipToNextStart)
  let variable = Pattern::new("two-variable", [
    Stage::new("first", Always, min=1, max=2),
    Stage::new("last", Always, min=1, max=3),
  ], 10L)
  assert_eq(variable.analysis().minimum_captures, 2)
  assert_eq(variable.analysis().maximum_captures, 5)
  assert_eq(variable.analysis().branching_risk, CombinatorialSelection)
}

///|
test "analysis reports guards and trailing absence" {
  let pattern = Pattern::new("guarded", [
    Stage::new("first", Always),
    Stage::new("last", Always, forbidden=Always),
  ], 10L, absence=Always)
  assert_eq(pattern.analysis().guarded_stages, 1)
  assert_true(pattern.analysis().has_absence)
  assert_true(pattern.stage("last").unwrap().forbidden() is Some(_))
  assert_true(pattern.absence() is Some(_))
}

///|
test "stage validates condition structure before taking ownership" {
  assert_true(
    (Some(Stage::new("invalid", Has(""))) catch { _ => None }) is None,
  )
  let cycle : Array[Condition] = []
  cycle.push(All(cycle))
  assert_true(
    (Some(Stage::new("cycle", All(cycle))) catch { _ => None }) is None,
  )
  assert_true(
    (Some(Stage::new("cycle-guard", Always, forbidden=All(cycle))) catch {
      _ => None
    })
    is None,
  )
}

///|
test "stage and pattern detach all nested condition arrays" {
  let children : Array[Condition] = [Kind("created")]
  let guard_children : Array[Condition] = [Kind("cancelled")]
  let absence_children : Array[Condition] = [Kind("late")]
  let first = Stage::new("first", All(children))
  let last = Stage::new("last", Always, forbidden=Any(guard_children))
  let pattern = Pattern::new("owned", [first, last], 10L, absence=All(absence_children))
  children.clear()
  guard_children.clear()
  absence_children.clear()
  match first.condition() {
    All(values) => assert_eq(values.length(), 1)
    _ => fail("expected conjunction")
  }
  match pattern.stage("first").unwrap().condition() {
    All(values) => values.clear()
    _ => fail("expected conjunction")
  }
  match pattern.stages()[0].condition() {
    All(values) => assert_eq(values.length(), 1)
    _ => fail("expected conjunction")
  }
  match pattern.stage("last").unwrap().forbidden() {
    Some(Any(values)) => {
      assert_eq(values.length(), 1)
      values.clear()
    }
    _ => fail("expected disjunction guard")
  }
  match pattern.stage("last").unwrap().forbidden() {
    Some(Any(values)) => assert_eq(values.length(), 1)
    _ => fail("expected detached guard")
  }
  match pattern.absence() {
    Some(All(values)) => {
      assert_eq(values.length(), 1)
      values.clear()
    }
    _ => fail("expected conjunction absence")
  }
  match pattern.absence() {
    Some(All(values)) => assert_eq(values.length(), 1)
    _ => fail("expected detached absence")
  }
}

///|
test "positive conditions can reference only previous completed captures" {
  let first = Stage::new("first", Kind("created"))
  let second = Stage::new("second", CaptureCompare("amount", Greater, "first", "amount"))
  assert_eq(Pattern::new("valid", [first, second], 10L).stage_names(), ["first", "second"])
  let self_reference = Stage::new("first", CaptureCount("first", Greater, 0))
  assert_true(
    (Some(Pattern::new("self", [self_reference], 10L)) catch { _ => None })
    is None,
  )
  let future_reference = Stage::new("first", CaptureCount("second", Equal, 1))
  assert_true(
    (Some(Pattern::new("forward", [future_reference, second], 10L)) catch {
      _ => None
    })
    is None,
  )
}

///|
test "guards use prior captures and trailing absence can use every stage" {
  let first = Stage::new("first", Kind("created"))
  let last = Stage::new("last", Kind("completed"), forbidden=CaptureCount("first", Equal, 1))
  let pattern = Pattern::new("valid", [first, last], 10L, absence=CaptureCount("last", Equal, 1))
  assert_eq(pattern.analysis().guarded_stages, 1)
  assert_true(pattern.analysis().has_absence)
  let invalid_guard = Stage::new("last", Always, forbidden=CaptureCount("last", Equal, 1))
  assert_true(
    (Some(Pattern::new("self-guard", [first, invalid_guard], 10L)) catch {
      _ => None
    })
    is None,
  )
  assert_true(
    (Some(Pattern::new("missing", [first], 10L, absence=CaptureCount("unknown", Equal, 1))) catch {
      _ => None
    })
    is None,
  )
}

///|
test "pattern rejects cyclic trailing absence before cloning" {
  let cycle : Array[Condition] = []
  cycle.push(Not(Any(cycle)))
  assert_true(
    (Some(Pattern::new("cycle", [Stage::new("first", Always)], 10L, absence=All(cycle))) catch {
      _ => None
    })
    is None,
  )
}
