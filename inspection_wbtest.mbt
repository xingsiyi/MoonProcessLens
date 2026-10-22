///|
test "inspection reports committed state and detaches diagnostic arrays" {
  let engine = Engine::new([pair_pattern()])
  input(engine, "a", 0L)
  ignore(engine.advance_watermark(0L))
  input(engine, "b", 3L)
  let report = engine.inspect()
  assert_eq(report.buffered(), 1)
  assert_eq(report.active_states(), 1)
  assert_eq(report.partitions()[0].earliest_deadline, Some(10L))
  let frontier = engine.frontier()
  assert_eq(frontier.items()[0].stage, Some("b"))
  frontier.items()[0].captures[0].events.clear()
  assert_eq(engine.frontier().items()[0].captures[0].events.length(), 1)
  assert_eq(report.active_states(), 1)
  ignore(engine.finish())
  assert_eq(report.active_states(), 1)
  assert_eq(engine.inspect().active_states(), 0)
}
