///|
test "program configuration roundtrip supports projected alerts" {
  let pattern = pair_pattern()
  let plan = ProjectionPlan::new(pattern, [
    { name: "duration", projection: Duration, },
  ])
  let program = Program::new([pattern], projections=[plan])
  let restored = parse_program(format_program(program))
  let engine = restored.engine()
  input(engine, "a", 0L)
  input(engine, "b", 1L)
  let batch = engine.advance_watermark(1L)
  assert_eq(restored.project(batch)[0].fields[0].value, Integer(1L))
  assert_eq(program_to_json(program), program_to_json(restored))
}

///|
test "program revalidates plans against matching pattern names and captures" {
  let original = pair_pattern()
  let plan = ProjectionPlan::new(original, [
    { name: "a", projection: CaptureSize("a"), },
  ])
  let replaced = Pattern::new("ab", [Stage::new("changed", Always)], 10L)
  assert_true(
    try {
      ignore(Program::new([replaced], projections=[plan]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(Program::new([original], projections=[plan, plan]))
      false
    } catch {
      _ => true
    },
  )
}
