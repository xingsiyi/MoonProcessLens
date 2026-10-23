///|
test "variant cache rebinds all evidence IDs and preserves uncached witnesses" {
  let log = model_log([["A", "X", "B"], ["A", "X", "B"]])
  let net = sequential_net()
  let cached = log.align_net(net)
  let full = log.align_net(net, reuse_variants=false)
  assert_true(!cached[0].reused_variant && cached[1].reused_variant)
  assert_eq(cached[1].visited_states, 0)
  assert_eq(cached[1].cost, full[1].cost)
  assert_true(cached[1].moves == full[1].moves)
  let actions = cached[1].moves
  actions.clear()
  assert_true(!cached[0].moves.is_empty())
}

///|
test "weighted input arcs and exact accepting marking reject leftover tokens" {
  let net = @processlens.PetriNet::new(
    ["p0", "p1"],
    [{ id: "a", activity: Some("A"), }],
    [
      { source: "p0", target: "a", weight: 2, },
      { source: "a", target: "p1", weight: 1, },
    ],
    [{ place: "p0", tokens: 3, }],
    [{ place: "p1", tokens: 1, }],
  )
  assert_eq(net.fire(net.initial_marking(), "a"), [1, 1])
  let report = net.analyze()
  assert_true(!report.final_reachable && !report.proper_completion)
  let failed = try {
    let _ = net_trace(["A"]).align_net(net)
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "model constructors reject invalid arcs duplicate markings and bad dimensions" {
  let failed = try {
    let _ = @processlens.PetriNet::new(
      ["p"],
      [{ id: "a", activity: Some("A"), }],
      [{ source: "p", target: "p", weight: 1, }],
      [],
      [],
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let failed = try {
    let _ = @processlens.PetriNet::new(
      ["p"],
      [],
      [],
      [{ place: "p", tokens: 1, }, { place: "p", tokens: 0, }],
      [],
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let failed = try {
    let _ = sequential_net().enabled([0])
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "BPMN typed constructor rejects ambiguous task joins and dangling endpoints" {
  let model = parallel_model()
  let nodes = model.nodes()
  nodes.push({ id: "other", kind: Task, activity: Some("X"), })
  let failed = try {
    let _ = @processlens.BpmnModel::new(nodes, model.flows())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "model discovery explicitly enforces candidate and prefix limits" {
  let log = model_log([["A", "B", "C", "D"], ["A", "C", "B", "D"]])
  let failed = try {
    let _ = log.discover_alpha(max_work=1)
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let failed = try {
    let _ = log.discover_prefix_net(max_nodes=2)
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_true(
    log.align_net(log.discover_alpha()).all(result => result.conforming),
  )
}

///|
test "same-label bounded response does not use prior or identical zero-duration event" {
  let log = @processlens.EventLog::new([
    @processlens.LogEvent::new("e1", "c", "A", 0L, 0L),
    @processlens.LogEvent::new("e2", "c", "A", 0L, 0L),
  ])
  let results = log.check_policies([
    Response(id="same", trigger="A", target="A", within_ms=Some(0L)),
  ])
  assert_eq(results[0].event_ids, ["e2"])
}

///|
test "policies parse strict config and enforce result and evidence budgets" {
  let policies = @processlens.parse_policies(
    "{\"policies\":[{\"id\":\"r\",\"kind\":\"response\",\"first\":\"A\",\"second\":\"B\",\"within_ms\":\"10\"}]}",
  )
  let log = model_log([["A"]])
  assert_eq(log.check_policies(policies)[0].status, Violated)
  let failed = try {
    let _ = log.check_policies(policies, max_findings=0)
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let failed = try {
    let _ = @processlens.parse_policies(
      "{\"policies\":[{\"id\":\"x\",\"kind\":\"unknown\",\"first\":\"A\",\"second\":\"B\"}]}",
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "XML comments namespaces numeric Unicode and security declarations" {
  let xml = "<?xml version='1.0'?><!--before--><x:log xmlns:x='http://www.xes-standard.org/'><x:trace><x:string key='concept:name' value='c'/><x:event><x:string key='concept:name' value='&#x1F680;'/><x:date key='time:timestamp' value='1970-01-01T00:00:00Z'/></x:event></x:trace></x:log><!--after-->"
  let log = @processlens.parse_xes(xml)
  assert_eq(log.traces()[0].activities(), ["🚀"])
  let failed = try {
    let _ = @processlens.parse_xes(
      xml.replace_all(old="version='1.0'", new="version='1.1'"),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let deep = StringBuilder()
  for _ in 0..<50 {
    deep.write_string("<log>")
  }
  for _ in 0..<50 {
    deep.write_string("</log>")
  }
  let failed = try {
    let _ = @processlens.parse_xes(deep.to_string())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "XES explicit omissions do not become empty apparently valid traces" {
  for
    xml in [
      "<log><trace><string key='concept:name' value='x'/></trace></log>", "<log><global scope='unknown'><string key='concept:name' value='default'/></global></log>",
      "<log><trace><string key='concept:name' value='x'/><event><string key='concept:name' value='A'/><date key='time:timestamp' value='2026-01-01T00:00:00.0001Z'/></event></trace></log>",
    ] {
    let failed = try {
      let _ = @processlens.parse_xes(xml)
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "analysis is complete when the last transition examination exactly meets budget" {
  let net = @processlens.PetriNet::new(
    ["p", "q"],
    [{ id: "a", activity: Some("A"), }],
    [
      { source: "p", target: "a", weight: 1, },
      { source: "a", target: "q", weight: 1, },
    ],
    [{ place: "p", tokens: 1, }],
    [{ place: "q", tokens: 1, }],
  )
  let result = net.analyze(limits={ states: 2, edges: 2, tokens_per_place: 1, })
  assert_true(result.complete && result.all_states_can_complete)
}

///|
test "PNML executable attributes cannot be silently parsed as ordinary arcs" {
  let text = sequential_net()
    .to_pnml()
    .replace_all(old="<arc id=", new="<arc type='inhibitor' id=")
  let failed = try {
    let _ = @processlens.parse_pnml(text)
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "XES exact millisecond trailing precision is accepted without rounding" {
  let xml = point_xes(
    "<event><string key='concept:name' value='A'/><date key='time:timestamp' value='1970-01-01T00:00:00.123000+00:00'/></event>",
  )
  assert_eq(@processlens.parse_xes(xml).traces()[0].events()[0].started(), 123L)
  let failed = try {
    let _ = @processlens.parse_xes(
      xml.replace_all(old=".123000", new=".123001"),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
