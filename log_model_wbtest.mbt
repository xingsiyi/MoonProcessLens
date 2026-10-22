///|
test "log ownership, interval ordering and original-occurrence ties" {
  let first = LogEvent::new("1", "b", "open", 10L, 30L)
  let second = LogEvent::new("2", "b", "parallel", 10L, 20L)
  let third = LogEvent::new("3", "b", "finish", 10L, 20L)
  let source = [first, second, third]
  let log = EventLog::new(source)
  source.clear()
  let traces = log.traces()
  assert_eq(traces[0].activities(), ["parallel", "finish", "open"])
  assert_eq(traces[0].cycle_time(), 20L)
  traces[0].events.clear()
  assert_eq(log.event_count(), 3)
  assert_eq(log.traces()[0].events().length(), 3)
  assert_eq(EventLog::new([]).case_count(), 0)
}

///|
test "invalid intervals, identity and capacity are explicit" {
  let bad = try {
    ignore(LogEvent::new("x", "c", "a", 4L, 3L))
    false
  } catch {
    _ => true
  }
  assert_true(bad)
  let event = LogEvent::new("x", "c", "a", 0L, 0L)
  assert_true(
    try {
      ignore(EventLog::new([event, event]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(EventLog::new([event], max_trace=0))
      false
    } catch {
      _ => true
    },
  )
  let other = LogEvent::new("y", "d", "b", 0L, 0L)
  assert_true(
    try {
      ignore(EventLog::new([event, other], max_cases=1))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "case activity and resource ordering is lexical rather than length first" {
  let log = EventLog::new([
    LogEvent::new("1", "z", "z", 0L, 1L, resource=Some("z")),
    LogEvent::new("2", "aa", "aa", 0L, 1L, resource=Some("aa")),
  ])
  assert_eq(log.traces()[0].id(), "aa")
  assert_eq(log.discover().nodes[0].activity, "aa")
  assert_eq(log.performance().activities[0].activity, "aa")
  assert_eq(log.performance().resources[0].resource, "aa")
}

///|
test "discovery counts loops, cases, starts and path boundaries" {
  let log = EventLog::new([
    LogEvent::new("1", "c1", "a", 0L, 1L),
    LogEvent::new("2", "c1", "a", 2L, 3L),
    LogEvent::new("3", "c1", "b", 4L, 5L),
    LogEvent::new("4", "c2", "a", 0L, 1L),
    LogEvent::new("5", "c2", "b", 2L, 3L),
  ])
  let graph = log.discover()
  assert_eq(graph.nodes[0], {
    activity: "a",
    occurrences: 3,
    cases: 2,
    starts: 2,
    ends: 0,
  })
  assert_eq(graph.edges[0], {
    source: "a",
    target: "a",
    occurrences: 1,
    cases: 1,
  })
  assert_eq(graph.edges[1].occurrences, 2)
  assert_eq(graph.frequent_edges(2).length(), 1)
  assert_eq(graph.variants.length(), 2)
  assert_true(path_identity(["a:b", "c"]) != path_identity(["a", "b:c"]))
  ignore(process_map_to_json(graph).stringify())
}
