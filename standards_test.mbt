///|
fn point_xes(events : String) -> String {
  "<log><trace><string key=\"concept:name\" value=\"case\"/>\{events}</trace></log>"
}

///|
test "XES completed interval export roundtrips resources ids Unicode and millisecond time" {
  let log = @processlens.EventLog::new([
    @processlens.LogEvent::new(
      "e1",
      "order&1",
      "审批/🚀",
      1709164800123L,
      1709164801456L,
      resource=Some("A\"B"),
    ),
    @processlens.LogEvent::new(
      "e2", "order&1", "完成", 1709164802000L, 1709164802000L,
    ),
  ])
  let exported = log.to_xes()
  let restored = @processlens.parse_xes(exported) catch {
    error => fail(error.to_repr().to_string())
  }
  assert_eq(@processlens.log_to_json(restored), @processlens.log_to_json(log))
}

///|
test "XES timezone normalizes exactly and rejects impossible dates" {
  let xml = point_xes(
    "<event><string key=\"concept:name\" value=\"A\"/><date key=\"time:timestamp\" value=\"1970-01-01T01:00:00.123+01:00\"/></event>",
  )
  let log = @processlens.parse_xes(xml)
  assert_eq(log.traces()[0].events()[0].started(), 123L)
  let bad = xml.replace_all(
    old="1970-01-01T01:00:00.123+01:00",
    new="2025-02-29T00:00:00Z",
  )
  let rejected = try {
    let _ = @processlens.parse_xes(bad)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "XES lifecycle pairs require matched identity and produce service interval" {
  let xml = point_xes(
    "<event><string key=\"concept:name\" value=\"A\"/><string key=\"lifecycle:transition\" value=\"start\"/><date key=\"time:timestamp\" value=\"1970-01-01T00:00:00Z\"/></event><event><string key=\"concept:name\" value=\"A\"/><string key=\"lifecycle:transition\" value=\"complete\"/><date key=\"time:timestamp\" value=\"1970-01-01T00:00:01Z\"/></event>",
  )
  let log = @processlens.parse_xes(xml, mode=LifecyclePairs)
  assert_eq(log.event_count(), 1)
  assert_eq(log.traces()[0].cycle_time(), 1000L)
  let rejected = try {
    let _ = @processlens.parse_xes(xml)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let unmatched = xml.replace_all(
    old="value=\"complete\"",
    new="value=\"start\"",
  )
  let rejected = try {
    let _ = @processlens.parse_xes(unmatched, mode=LifecyclePairs)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "XML rejects DTD custom entities namespace spoofing and duplicate attributes" {
  let invalid = [
    "<!DOCTYPE log SYSTEM 'file:///secret'><log/>", "<log>&custom;</log>", "<log xmlns='urn:wrong'/>",
    "<log x='a' x='b'/>", "<log><trace></log>", "<log/><log/>", "<log><x:trace/></log>",
    "<log>&#0;</log>",
  ]
  for xml in invalid {
    let rejected = try {
      let _ = @processlens.parse_xes(xml)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "BPMN conditional flows unsupported events and mixed gateways fail explicitly" {
  let model = parallel_model()
  let text = model.to_bpmn()
  for
    xml in [
      text.replace_all(old="<startEvent", new="<intermediateCatchEvent"),
      text.replace_all(
        old="isExecutable=\"false\"",
        new="isExecutable=\"true\"",
      ),
      text.replace_all(old="<parallelGateway", new="<inclusiveGateway"),
    ] {
    let rejected = try {
      let _ = @processlens.parse_bpmn(xml)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "PNML requires explicit accepting marking and refuses non ordinary arcs" {
  let xml = sequential_net().to_pnml()
  let invalid = xml.replace_all(
    old="http://www.pnml.org/version-2009/grammar/ptnet",
    new="coloured",
  )
  let rejected = try {
    let _ = @processlens.parse_pnml(invalid)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "business policies separate true violations unknown resources and non applicability" {
  let log = @processlens.EventLog::new([
    @processlens.LogEvent::new(
      "a",
      "one",
      "create",
      0L,
      2L,
      resource=Some("alice"),
    ),
    @processlens.LogEvent::new(
      "b",
      "one",
      "approve",
      5L,
      6L,
      resource=Some("alice"),
    ),
    @processlens.LogEvent::new("c", "two", "create", 0L, 2L),
    @processlens.LogEvent::new(
      "d",
      "two",
      "approve",
      10L,
      11L,
      resource=Some("bob"),
    ),
  ])
  let results = log.check_policies([
    Response(id="sla", trigger="create", target="approve", within_ms=Some(5L)),
    Precedence(id="order", trigger="approve", required="create"),
    SeparationOfDuties(id="duties", first="create", second="approve"),
    NotCoexist(id="exclusion", first="cancel", second="ship"),
  ])
  assert_eq(results[0].status, Satisfied)
  assert_eq(results[1].status, Satisfied)
  assert_eq(results[2].status, Violated)
  assert_eq(results[3].status, NotApplicable)
  assert_eq(results[4].status, Violated)
  assert_eq(results[6].status, Inconclusive)
}

///|
test "bounded response skips overlapping targets and respects strict event order" {
  let log = @processlens.EventLog::new([
    @processlens.LogEvent::new("a", "one", "A", 0L, 10L),
    @processlens.LogEvent::new("b", "one", "B", 5L, 6L),
    @processlens.LogEvent::new("c", "one", "B", 11L, 12L),
  ])
  assert_eq(
    log.check_policies([
      Response(id="r", trigger="A", target="B", within_ms=Some(2L)),
    ])[0].status,
    Satisfied,
  )
  let zero = model_log([["A"]])
  assert_eq(
    zero.check_policies([
      Response(id="r", trigger="A", target="A", within_ms=Some(0L)),
    ])[0].status,
    Violated,
  )
}

///|
test "case filtering preserves histories and cohort total variation is exact" {
  let before = model_log([["A", "B"], ["A", "B"], ["A", "C"]])
  let filtered = before.select_cases({
    ..@processlens.CaseSelection::all(),
    require_activities: ["B"],
  })
  assert_eq(filtered.case_count(), 2)
  assert_eq(filtered.event_count(), 4)
  assert_eq(before.case_count(), 3)
  assert_eq(before.compare_cohort(before).total_variation, 0.0)
  let after = model_log([["X"]])
  assert_eq(before.compare_cohort(after).total_variation, 1.0)
}

///|
test "observed resource network counts occurrences separately from case coverage" {
  let log = @processlens.EventLog::new([
    @processlens.LogEvent::new("a", "c", "A", 0L, 1L, resource=Some("alice")),
    @processlens.LogEvent::new("b", "c", "B", 2L, 3L, resource=Some("bob")),
    @processlens.LogEvent::new("c", "c", "C", 4L, 5L, resource=Some("alice")),
    @processlens.LogEvent::new("d", "c", "D", 6L, 7L, resource=Some("bob")),
  ])
  let network = log.resource_handoffs()
  assert_eq(network[0].source, "alice")
  assert_eq(network[0].occurrences, 2)
  assert_eq(network[0].cases, 1)
}
