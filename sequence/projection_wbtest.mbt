///|
test "alert projection preserves integer totals and named capture values" {
  let pattern = Pattern::new(
    "p",
    [Stage::new("items", Kind("item"), min=2, max=2)],
    10L,
  )
  let plan = ProjectionPlan::new(pattern, [
    { name: "owner", projection: EntityKey, },
    { name: "count", projection: CaptureSize("items"), },
    { name: "sum", projection: TotalInteger("items", "amount"), },
    { name: "first", projection: FirstField("items", "amount"), },
  ])
  let engine = Engine::new([pattern])
  ignore(
    engine.push(
      Event::new("a", "customer", 0L, "item", fields=[
        { name: "amount", value: Integer(9007199254740993L), },
      ]),
    ),
  )
  ignore(
    engine.push(
      Event::new("b", "customer", 1L, "item", fields=[
        { name: "amount", value: Integer(2L), },
      ]),
    ),
  )
  let result = plan.apply(engine.advance_watermark(1L).matches()[0])
  assert_eq(result[2].value, Integer(9007199254740995L))
  assert_eq(result[3].value, Integer(9007199254740993L))
  assert_true(
    try {
      ignore(checked_integer_sum(9223372036854775807L, 1L))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(checked_integer_sum(-9223372036854775808L, -1L))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "decimal average avoids overflow from a finite average" {
  let events = [
    Event::new("a", "k", 0L, "x", fields=[
      { name: "x", value: Decimal(1.0e308), },
    ]),
    Event::new("b", "k", 1L, "x", fields=[
      { name: "x", value: Decimal(1.0e308), },
    ]),
  ]
  let result = project_aggregate(AverageDecimal("s", "x"), events, "x")
  assert_eq(result, Decimal(1.0e308))
  assert_true(
    try {
      ignore(project_aggregate(TotalDecimal("s", "x"), events, "x"))
      false
    } catch {
      _ => true
    },
  )
}
