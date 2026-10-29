///|
test "resource sweep counts cross-case overlaps and folds simultaneous boundaries" {
  let log = EventLog::new([
    LogEvent::new("a", "c1", "A", 0L, 10L, resource=Some("worker")),
    LogEvent::new("b", "c2", "B", 5L, 15L, resource=Some("worker")),
    LogEvent::new("c", "c3", "C", 10L, 20L, resource=Some("worker")),
    LogEvent::new("z", "c3", "Z", 10L, 10L, resource=Some("worker")),
  ])
  let timeline = log.resource_timeline("worker", 0L, 25L)
  assert_eq(timeline.length(), 4)
  assert_eq(timeline[0].active, 1)
  assert_eq(timeline[1].started, 5L)
  assert_eq(timeline[1].completed, 15L)
  assert_eq(timeline[1].active, 2)
  assert_eq(timeline[3].active, 0)
  assert_eq(log.resource_timeline("unknown", 0L, 25L).length(), 1)
}

///|
test "flow windows conserve clipped case work and distinguish completion boundaries" {
  let log = EventLog::new([
    LogEvent::new("a", "c1", "A", 0L, 10L),
    LogEvent::new("b", "c2", "B", 5L, 15L),
    LogEvent::new("c", "c3", "C", 10L, 10L),
  ])
  let windows = log.flow_windows(0L, 20L, 10L)
  assert_eq(windows.length(), 2)
  assert_eq(windows[0].cases_started, 2)
  assert_eq(windows[0].cases_completed, 0)
  assert_eq(windows[0].active_at_start, 1)
  assert_eq(windows[0].active_before_end, 2)
  assert_eq(windows[0].observed_work_area, 15.0)
  assert_eq(windows[1].cases_completed, 3)
  assert_eq(windows[1].completed_cycles.count, 3)
  assert_eq(windows[1].observed_work_area, 5.0)
  assert_eq(windows[1].mean_observed_wip, 0.5)
  assert_eq(log.flow_windows(3L, 13L, 7L)[1].completed, 13L)
}

///|
test "workload windows reject invalid windows and bound output and cross product work" {
  let log = EventLog::new([LogEvent::new("a", "c", "A", 0L, 1L)])
  let invalid = try {
    ignore(log.flow_windows(0L, 20L, 0L))
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
  let limited = try {
    ignore(log.flow_windows(0L, 100L, 1L, max_windows=10))
    false
  } catch {
    _ => true
  }
  assert_true(limited)
  let work = try {
    ignore(log.flow_windows(0L, 100L, 1L, max_work=10))
    false
  } catch {
    _ => true
  }
  assert_true(work)
  let segments = try {
    ignore(log.resource_timeline("none", 0L, 10L, max_segments=0))
    false
  } catch {
    _ => true
  }
  assert_true(segments)
}
