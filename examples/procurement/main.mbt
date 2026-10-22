///|
fn main raise {
  // Unordered ERP observations: case IDs prevent cross-order adjacency.
  let log = @lens.EventLog::new([
    @lens.LogEvent::new("a3", "order-a", "ship", 10L, 11L),
    @lens.LogEvent::new("b2", "order-b", "ship", 3L, 4L),
    @lens.LogEvent::new("a1", "order-a", "create", 0L, 1L),
    @lens.LogEvent::new("a2", "order-a", "approve", 4L, 6L),
    @lens.LogEvent::new("b1", "order-b", "create", 0L, 1L),
  ])
  let graph = log.discover()
  assert_eq(graph.variants.length(), 2)
  let model = @lens.ReferencePath::new("approved-order", [
    "create", "approve", "ship",
  ])
  let traces = log.traces()
  let compliant = traces[0].align([model])
  let deviation = traces[1].align([model])
  assert_eq(compliant.cost, 0)
  assert_eq(deviation.cost, 1)
  assert_true(deviation.moves.contains(@lens.Missing(activity="approve")))
  assert_eq(log.performance().cases[0].idle_time, 7L)
  println(@lens.process_map_to_json(graph).stringify())
  println(@lens.alignment_to_json(deviation).stringify())
  println(@lens.performance_to_json(log.performance()).stringify())
}
