///|
fn main raise {
  let log = @lens.EventLog::new([
    @lens.LogEvent::new(
      "build",
      "run-42",
      "build",
      1L,
      10L,
      resource=Some("runner"),
    ),
    @lens.LogEvent::new(
      "test",
      "run-42",
      "tests",
      2L,
      4L,
      resource=Some("runner"),
    ),
    @lens.LogEvent::new(
      "pack",
      "run-42",
      "package",
      12L,
      15L,
      resource=Some("runner"),
    ),
  ])
  let report = log.performance()
  // Summing service would overstate occupied wall time by the overlapping tests.
  assert_eq(report.cases[0].cycle_time, 14L)
  assert_eq(report.cases[0].busy_union, 12L)
  assert_eq(report.cases[0].service_work, 14.0)
  assert_eq(report.cases[0].idle_time, 2L)
  assert_eq(report.resources[0].maximum_concurrency, 2)
  let roundtrip = @lens.parse_log(@lens.log_to_json(log).stringify())
  assert_eq(roundtrip.event_count(), 3)
  println(@lens.performance_to_json(report).stringify())
}
