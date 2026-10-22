///|
fn main raise {
  let log = @lens.EventLog::new([
    @lens.LogEvent::new("a1", "job-a", "receive", 0L, 1L),
    @lens.LogEvent::new("a2", "job-a", "repair", 2L, 6L, resource=Some("bench")),
    @lens.LogEvent::new("a3", "job-a", "inspect", 7L, 8L),
    @lens.LogEvent::new("b1", "job-b", "receive", 0L, 1L),
    @lens.LogEvent::new("b2", "job-b", "repair", 2L, 4L, resource=Some("bench")),
    @lens.LogEvent::new("b3", "job-b", "inspect", 5L, 6L),
    @lens.LogEvent::new(
      "b4",
      "job-b",
      "repair",
      7L,
      10L,
      resource=Some("bench"),
    ),
    @lens.LogEvent::new("b5", "job-b", "inspect", 11L, 12L),
  ])
  let standard = @lens.ReferencePath::new("standard", [
    "receive", "repair", "inspect",
  ])
  let rework = @lens.ReferencePath::new("one-rework", [
    "receive", "repair", "inspect", "repair", "inspect",
  ])
  let cases = log.traces()
  assert_eq(cases[0].align([standard, rework]).reference, "standard")
  assert_eq(cases[1].align([standard, rework]).reference, "one-rework")
  assert_eq(log.performance().resources[0].maximum_concurrency, 2)
  assert_eq(log.discover().variants.length(), 2)
  println(@lens.process_map_to_json(log.discover()).stringify())
  println(@lens.performance_to_json(log.performance()).stringify())
}
