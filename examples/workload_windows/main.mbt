///|
fn main raise {
  let log = @p.EventLog::new([
    @p.LogEvent::new("a", "ticket-a", "repair", 0L, 10L, resource=Some("team")),
    @p.LogEvent::new("b", "ticket-b", "repair", 5L, 15L, resource=Some("team")),
  ])
  let occupied = log.resource_timeline("team", 0L, 20L)
  assert_eq(occupied[1].active, 2)
  let windows = log.flow_windows(0L, 20L, 10L)
  assert_eq(windows[0].mean_observed_wip, 1.5)
  assert_eq(windows[1].cases_completed, 2)
  println(
    "Observed team concurrency and whole-case flow windows distinguish overlap, carry-in and completions",
  )
}
