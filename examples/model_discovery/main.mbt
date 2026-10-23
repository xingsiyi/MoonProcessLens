///|
fn main raise {
  let events = []
  // A production line has independent quality and packaging branches.
  let paths = [
    ["receive", "quality", "package", "ship"],
    ["receive", "package", "quality", "ship"],
  ]
  for c, labels in paths {
    for i, activity in labels {
      events.push(
        @lens.LogEvent::new(
          "e\{c}-\{i}",
          "order\{c}",
          activity,
          (i * 10).to_int64(),
          (i * 10 + 1).to_int64(),
        ),
      )
    }
  }
  let log = @lens.EventLog::new(events)
  let net = log.discover_alpha()
  let report = net.analyze()
  assert_true(report.complete && report.all_states_can_complete)
  let results = log.align_net(net)
  assert_true(results.all(result => result.conforming))
  let deviation = @lens.CaseTrace::new("bad", [
    @lens.LogEvent::new("x1", "bad", "receive", 0L, 1L),
    @lens.LogEvent::new("x2", "bad", "package", 2L, 3L),
    @lens.LogEvent::new("x3", "bad", "ship", 4L, 5L),
  ])
  assert_eq(deviation.align_net(net).cost, 1)
  let exchange = @lens.parse_pnml(net.to_pnml())
  assert_true(log.align_net(exchange).all(result => result.conforming))
  println(
    "Discovery: Alpha parallel model; both interleavings conform; missing quality costs 1; PNML roundtrip passed",
  )
  println(@lens.model_analysis_to_json(report).stringify())
}
