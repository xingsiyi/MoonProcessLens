///|
fn main raise {
  let events : Array[@lens.LogEvent] = []
  for i = 0; i < 20000; i = i + 1 {
    let base = i.to_int64() * 100L
    for j, activity in ["create", "approve", "ship"] {
      events.push(
        @lens.LogEvent::new(
          "\{i}/\{j}",
          "order/\{i}",
          activity,
          base + j.to_int64() * 10L,
          base + j.to_int64() * 10L + 5L,
          resource=Some("shared-worker"),
        ),
      )
    }
  }
  let started = @env.now()
  let log = @lens.EventLog::new(events, max_cases=20000)
  let graph = log.discover()
  let report = log.performance()
  let aligned = log.align([
    @lens.ReferencePath::new("normal", ["create", "approve", "ship"]),
  ])
  assert_eq(graph.variants.length(), 1)
  assert_eq(graph.edges[0].occurrences, 20000)
  assert_eq(aligned.length(), 20000)
  assert_true(aligned.all(result => result.cost == 0))
  assert_eq(report.resources[0].maximum_concurrency, 1)
  assert_true(report.cycle_times.p95 == Some(25L))
  println(
    "process_events=60000 cases=20000 variants=1 aligned=20000 elapsed_ms=\{@env.now()-started}",
  )
}
