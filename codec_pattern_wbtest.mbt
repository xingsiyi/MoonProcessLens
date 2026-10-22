///|
test "pattern wire roundtrip preserves every condition and selection policy" {
  let conditions : Array[Condition] = [
    Always, Kind("a"), Has("x"), Compare("x", Greater, Integer(9007199254740993L)),
    FieldCompare("x", Equal, "y"), CaptureCompare("x", Less, "first", "x"),
    CaptureCount("first", GreaterEqual, 1), TextPrefix("s", "中"),
    TextContains("s", "文"), All([Kind("a"), Has("x")]), Any([]), Not(Has("z")),
  ]
  for condition in conditions {
    assert_eq(condition_from_json(condition_to_json(condition)), condition)
    assert_eq(parse_condition(format_condition(condition)), condition)
    for policy in [NoSkip, SkipToNextStart, SkipPastLast] {
      let pattern = Pattern::new("wire", [
        Stage::new("first", Always),
        Stage::new("second", condition, min=0, max=3, contiguity=SkipAny, forbidden=Kind("cancel")),
      ], 10L, after_match=policy, absence=Kind("reject"))
      let restored = parse_pattern(format_pattern(pattern))
      assert_eq(pattern_to_json(restored), pattern_to_json(pattern))
    }
  }
}

///|
test "pattern schema rejects typos future versions and forward capture use" {
  let valid = pattern_to_json(pair_pattern())
  let object = codec_object(valid, "test")
  object.set("schema_version", Json::number(2.0))
  assert_true(try { ignore(pattern_from_json(valid)); false } catch { _ => true })
  object.set("schema_version", Json::number(1.0))
  object.set("extra", Json::null())
  assert_true(try { ignore(pattern_from_json(valid)); false } catch { _ => true })
  assert_true(try {
    ignore(parse_condition("{\"type\":\"kind\",\"value\":\"a\",\"value\":\"b\"}")); false
  } catch { _ => true })
}

///|
test "condition JSON cycles and excessive nesting terminate with resource error" {
  let object : Map[String, Json] = Map([("type", Json::string("not"))])
  let cyclic = Json::object(object)
  object.set("condition", cyclic)
  assert_true(try { ignore(condition_from_json(cyclic)); false } catch { Resource(..) => true; _ => false })
  let mut condition = Always
  for _ in 0..<31 { condition = All([condition]) }
  assert_eq(parse_condition(format_condition(condition)), condition)
}
