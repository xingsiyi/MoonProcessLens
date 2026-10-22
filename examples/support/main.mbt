///|
fn main raise {
  let log = @lens.EventLog::new([
    @lens.LogEvent::new("1", "ticket-1", "open", 0L, 1L),
    @lens.LogEvent::new(
      "2",
      "ticket-1",
      "investigate",
      2L,
      4L,
      resource=Some("support"),
    ),
    @lens.LogEvent::new(
      "3",
      "ticket-1",
      "investigate",
      5L,
      8L,
      resource=Some("support"),
    ),
    @lens.LogEvent::new("4", "ticket-1", "close", 9L, 10L),
  ])
  let graph = log.discover()
  assert_true(
    graph.edges.any(edge => {
      edge.source == "investigate" && edge.target == "investigate"
    }),
  )
  let result = log.traces()[0].align([
    @lens.ReferencePath::new("single-investigation", [
      "open", "investigate", "close",
    ]),
  ])
  assert_eq(result.cost, 1)
  let report = log.performance()
  assert_true(report.resources[0].service.p95 == Some(3L))
  println(@lens.alignment_to_json(result).stringify())
  println(@lens.performance_to_json(report).stringify())
}
