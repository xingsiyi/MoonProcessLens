///|
fn main raise {
  let original = @lens.EventLog::new([
    @lens.LogEvent::new(
      "a",
      "ticket1",
      "create",
      1700000000000L,
      1700000001000L,
      resource=Some("alice"),
    ),
    @lens.LogEvent::new(
      "b",
      "ticket1",
      "approve",
      1700000010000L,
      1700000011000L,
      resource=Some("bob"),
    ),
    @lens.LogEvent::new(
      "c",
      "ticket2",
      "create",
      1700000020000L,
      1700000021000L,
      resource=Some("alice"),
    ),
    @lens.LogEvent::new(
      "d",
      "ticket2",
      "approve",
      1700000080000L,
      1700000081000L,
      resource=Some("alice"),
    ),
  ])
  let log = @lens.parse_xes(original.to_xes())
  assert_eq(@lens.log_to_json(original), @lens.log_to_json(log))
  let policies : Array[@lens.ProcessPolicy] = [
    Response(
      id="approval-sla",
      trigger="create",
      target="approve",
      within_ms=Some(30000L),
    ),
    SeparationOfDuties(id="four-eyes", first="create", second="approve"),
  ]
  let report = log.check_policies(policies)
  assert_true(report[0].status == Satisfied && report[1].status == Satisfied)
  assert_true(report[2].status == Violated && report[3].status == Violated)
  let slow = log.select_cases({
    ..@lens.CaseSelection::all(),
    minimum_cycle: Some(30000L),
  })
  assert_eq(slow.case_count(), 1)
  let network = log.resource_handoffs()
  assert_eq(network.length(), 1)
  assert_eq(network[0].source, "alice")
  println(
    "XES + business audit: delayed self-approval found; slow-case cohort and resource handoff verified",
  )
  println(@lens.policy_results_to_json(report).stringify())
}
