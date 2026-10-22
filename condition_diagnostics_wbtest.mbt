///|
test "standalone evaluation rejects cyclic and deep mutable ASTs" {
  let children : Array[Condition] = []
  let cyclic = All(children)
  children.push(cyclic)
  let event = Event::new("e", "k", 0L, "a")
  assert_true(try { ignore(cyclic.evaluate(event, [])); false } catch { Resource(..) => true; _ => false })
}

///|
test "diagnostic mode evaluates all siblings without leaking field values" {
  let condition = All([Compare("secret", Equal, Text("never-copy")), Has("missing")])
  let event = Event::new("e", "k", 0L, "a", fields=[{ name: "secret", value: Integer(1L) }])
  let report = condition.explain(event)
  assert_true(!report.matched())
  assert_eq(report.notes().length(), 3)
  assert_eq(report.notes()[0].reason, "incompatible-types")
  assert_eq(report.notes()[1].reason, "missing-field")
  assert_true(!evaluation_to_json(report).stringify().contains("secret"))
  assert_true(!evaluation_to_json(report).stringify().contains("never-copy"))
}
