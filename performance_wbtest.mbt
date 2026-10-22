///|
test "performance distinguishes service work, interval union and true idle" {
  let log = EventLog::new([
    LogEvent::new("1", "case", "a", 0L, 10L, resource=Some("worker")),
    LogEvent::new("2", "case", "b", 2L, 4L, resource=Some("worker")),
    LogEvent::new("3", "case", "c", 12L, 15L, resource=Some("worker")),
  ])
  let report = log.performance()
  assert_eq(report.cases[0].cycle_time, 15L)
  assert_eq(report.cases[0].busy_union, 13L)
  assert_eq(report.cases[0].idle_time, 2L)
  assert_eq(report.cases[0].service_work, 15.0)
  assert_eq(report.cases[0].overlapping_starts, 1)
  assert_eq(report.resources[0].maximum_concurrency, 2)
  assert_eq(report.handoffs[0].overlapping_pairs, 1)
  // Adjacent b->c gap is 8; actual whole-case idle is only 2 because a lasts 10.
  assert_true(report.handoffs[1].positive_gap.maximum == Some(8L))
  assert_true(EventLog::new([]).performance().cycle_times.mean == None)
  assert_eq(CaseTrace::new("empty", []).performance().idle_time, 0L)
  ignore(performance_to_json(report).stringify())
}

///|
test "half-open intervals end before simultaneous starts and point events consume no resource" {
  let log = EventLog::new([
    LogEvent::new("1", "c1", "a", 0L, 2L, resource=Some("r")),
    LogEvent::new("2", "c2", "a", 2L, 4L, resource=Some("r")),
    LogEvent::new("3", "c3", "point", 2L, 2L, resource=Some("r")),
  ])
  assert_eq(log.performance().resources[0].maximum_concurrency, 1)
  assert_true(duration_distribution([4L, 1L, 3L, 2L]).median == Some(2L))
  assert_true(duration_distribution([4L, 1L, 3L, 2L]).p95 == Some(4L))
}

///|
test "interval union and sweep agree with independent integer-slot oracle" {
  for a = 0; a <= 4; a = a + 1 {
    for b = a; b <= 4; b = b + 1 {
      for c = 0; c <= 4; c = c + 1 {
        for d = c; d <= 4; d = d + 1 {
          let events = [
            LogEvent::new("1", "c", "a", a.to_int64(), b.to_int64()),
            LogEvent::new("2", "c", "b", c.to_int64(), d.to_int64()),
          ]
          let trace = EventLog::new(events).traces()[0]
          let mut occupied = 0L
          let mut maximum = 0
          for slot = 0; slot < 4; slot = slot + 1 {
            let count = (if a <= slot && slot < b { 1 } else { 0 }) +
              (if c <= slot && slot < d { 1 } else { 0 })
            if count > 0 {
              occupied = occupied + 1L
            }
            if count > maximum {
              maximum = count
            }
          }
          assert_eq(trace.performance().busy_union, occupied)
          assert_eq(resource_concurrency(events), maximum)
        }
      }
    }
  }
}
