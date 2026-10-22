///|
test "projection schema validates names types and exact record encoding" {
  let pattern = pair_pattern()
  let projections : Array[Projection] = [EntityKey, PatternName, StartTime, EndTime, Duration, AbsenceMatch, CaptureSize("a"), FirstField("a", "x"), LastField("a", "x"), TotalInteger("a", "x"), TotalDecimal("a", "x"), MinimumField("a", "x"), MaximumField("a", "x"), AverageDecimal("a", "x")]
  for projection in projections {
    let plan = ProjectionPlan::new(pattern, [{ name: "out", projection }])
    assert_eq(projection_from_json(pattern, projection_to_json(plan)).columns()[0].projection, projection)
  }
  let json = projected_record_to_json([{ name: "id", value: Integer(9007199254740993L) }])
  assert_true(json.stringify().contains("9007199254740993"))
  assert_true(try { ignore(projected_record_to_json([{ name: "x", value: NullValue }, { name: "x", value: NullValue }])); false } catch { _ => true })
}
