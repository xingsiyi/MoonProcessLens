///|
fn predicate_sample_event(kind~ : String = "login") -> Event raise CepError {
  Event::new("sample", "account", 10L, kind, fields=[
    { name: "n", value: Integer(9007199254740993L) },
    { name: "smaller", value: Integer(9007199254740992L) },
    { name: "decimal", value: Decimal(1.0) },
    { name: "flag", value: Boolean(true) },
    { name: "null", value: NullValue },
    { name: "route", value: Text("管理/API/用户") },
  ])
}

///|
test "conditions compare integers exactly and reject cross type coercion" {
  let event = predicate_sample_event()
  for condition in [
    Compare("n", Equal, Integer(9007199254740993L)),
    Compare("n", NotEqual, Integer(9007199254740992L)),
    Compare("n", Greater, Integer(9007199254740992L)),
    Compare("n", GreaterEqual, Integer(9007199254740993L)),
    Compare("n", Less, Integer(9007199254740994L)),
    Compare("n", LessEqual, Integer(9007199254740993L)),
    FieldCompare("n", Greater, "smaller"),
    Compare("flag", Equal, Boolean(true)),
    Compare("null", Equal, NullValue),
  ] {
    condition.validate([])
    assert_true(condition.evaluate(event, []))
  }
  for condition in [
    Compare("n", Equal, Integer(9007199254740992L)),
    Compare("n", Equal, Decimal(9007199254740992.0)),
    Compare("n", NotEqual, Decimal(1.0)),
    FieldCompare("n", Greater, "decimal"),
    Compare("flag", Greater, Boolean(false)),
    Compare("null", NotEqual, NullValue),
    Compare("null", GreaterEqual, NullValue),
    Compare("decimal", Less, Integer(2L)),
  ] {
    condition.validate([])
    assert_true(!condition.evaluate(event, []))
  }
}

///|
test "missing fields are false comparisons and null remains present" {
  let event = predicate_sample_event()
  assert_true(Has("null").evaluate(event, []))
  assert_true(!Has("missing").evaluate(event, []))
  for condition in [
    Compare("missing", Equal, NullValue),
    Compare("missing", NotEqual, Integer(1L)),
    FieldCompare("n", NotEqual, "missing"),
    FieldCompare("missing", Equal, "missing"),
  ] {
    assert_true(!condition.evaluate(event, []))
  }
  assert_true(Not(Compare("missing", Equal, Integer(1L))).evaluate(event, []))
  assert_true(
    !All([Has("missing"), Not(Compare("missing", Equal, Integer(1L)))])
      .evaluate(event, []),
  )
}

///|
test "capture predicates read the last event without coercion" {
  let first = Event::new("first", "account", 0L, "failure", fields=[
    { name: "value", value: Integer(9007199254740992L) },
  ])
  let last = Event::new("last", "account", 1L, "failure", fields=[
    { name: "value", value: Integer(9007199254740993L) },
  ])
  let captures : Array[Capture] = [
    { name: "failures", events: [first, last] },
    { name: "optional", events: [] },
  ]
  let event = predicate_sample_event()
  let equal_last = CaptureCompare("n", Equal, "failures", "value")
  equal_last.validate(["failures", "optional"])
  assert_true(equal_last.evaluate(event, captures))
  assert_true(CaptureCount("failures", Equal, 2).evaluate(event, captures))
  assert_true(CaptureCount("failures", Greater, 1).evaluate(event, captures))
  assert_true(CaptureCount("optional", Equal, 0).evaluate(event, captures))
  for condition in [
    CaptureCompare("n", Equal, "optional", "value"),
    CaptureCompare("n", NotEqual, "optional", "value"),
    CaptureCompare("missing", Equal, "failures", "value"),
    CaptureCompare("n", Equal, "failures", "missing"),
    CaptureCompare("n", NotEqual, "unknown", "value"),
    CaptureCompare("decimal", Equal, "failures", "value"),
    CaptureCount("unknown", Equal, 0),
    CaptureCount("unknown", NotEqual, 0),
  ] {
    assert_true(!condition.evaluate(event, captures))
  }
}

///|
test "text conditions support Unicode and empty needles without coercion" {
  let event = predicate_sample_event()
  for condition in [
    Kind("login"),
    TextPrefix("route", "管理/"),
    TextContains("route", "用户"),
    TextPrefix("route", ""),
    TextContains("route", ""),
    All([]),
    Any([Kind("other"), Has("route")]),
    Not(Kind("other")),
  ] {
    condition.validate([])
    assert_true(condition.evaluate(event, []))
  }
  for condition in [
    Kind("other"),
    TextPrefix("route", "API"),
    TextContains("route", "未找到"),
    TextPrefix("n", "9007"),
    TextContains("missing", ""),
    TextPrefix("null", ""),
    Any([]),
    All([Always, Kind("other")]),
  ] {
    condition.validate([])
    assert_true(!condition.evaluate(event, []))
  }
}

///|
test "validation checks all branches and earlier capture scope" {
  for condition in [
    CaptureCount("future", Equal, 0),
    CaptureCompare("n", Equal, "future", "n"),
    Any([Always, CaptureCount("future", Equal, 0)]),
    All([Not(Always), CaptureCompare("n", Equal, "future", "n")]),
  ] {
    assert_true(try { condition.validate(["earlier"]); false } catch { _ => true })
  }
  for condition in [
    CaptureCount("earlier", Equal, 0),
    CaptureCompare("n", Equal, "earlier", "n"),
  ] {
    condition.validate(["earlier"])
  }
  // Stage construction can validate shape before pattern capture scope exists.
  validate_condition_structure(CaptureCompare("n", Equal, "future", "n"))
}

///|
test "validation rejects invalid labels counts and nonfinite constants" {
  for condition in [
    Kind(""),
    Kind("bad\nkind"),
    Has(""),
    Compare("bad\nfield", Equal, Integer(1L)),
    Compare("n", Equal, Decimal(@double.not_a_number)),
    FieldCompare("n", Equal, ""),
    CaptureCompare("n", Equal, "prior", ""),
    CaptureCompare("n", Equal, "", "value"),
    CaptureCount("prior", Equal, -1),
    TextPrefix("", "prefix"),
    TextContains("", "part"),
  ] {
    assert_true(try { condition.validate(["prior"]); false } catch { _ => true })
  }
}

///|
test "condition node and depth budgets accept exact boundaries" {
  let mut deep = Always
  for _ in 0..<31 {
    deep = Not(deep)
  }
  deep.validate([])
  assert_true(try { Not(deep).validate([]); false } catch { _ => true })
  let wide : Array[Condition] = []
  for _ in 0..<511 {
    wide.push(Always)
  }
  All(wide).validate([])
  wide.push(Always)
  assert_true(try { All(wide).validate([]); false } catch { _ => true })
}

///|
test "cyclic condition arrays are rejected before clone or evaluation" {
  let children : Array[Condition] = []
  let cyclic = All(children)
  children.push(cyclic)
  assert_true(try { cyclic.validate([]); false } catch { _ => true })
  assert_true(try { validate_condition_structure(cyclic); false } catch { _ => true })
}

///|
test "condition cloning detaches every nested mutable child array" {
  let nested : Array[Condition] = [Kind("login")]
  let outer : Array[Condition] = [Not(Any(nested))]
  let original = All(outer)
  original.validate([])
  let detached = clone_condition(original)
  let event = predicate_sample_event()
  assert_true(!detached.evaluate(event, []))
  nested.clear()
  assert_true(original.evaluate(event, []))
  assert_true(!detached.evaluate(event, []))
  outer.clear()
  assert_true(original.evaluate(event, []))
  assert_true(!detached.evaluate(event, []))
}
