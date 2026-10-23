///|
fn net_trace(labels : Array[String]) -> @processlens.CaseTrace raise {
  let events = []
  for i, label in labels {
    events.push(
      @processlens.LogEvent::new(
        "e\{i}",
        "case",
        label,
        i.to_int64() * 10L,
        i.to_int64() * 10L + 1L,
      ),
    )
  }
  @processlens.CaseTrace::new("case", events)
}

///|
fn model_log(paths : Array[Array[String]]) -> @processlens.EventLog raise {
  let events = []
  for c, labels in paths {
    for i, label in labels {
      events.push(
        @processlens.LogEvent::new(
          "e\{c}-\{i}",
          "case\{c}",
          label,
          i.to_int64() * 10L,
          i.to_int64() * 10L + 1L,
        ),
      )
    }
  }
  @processlens.EventLog::new(events)
}

///|
fn sequential_net() -> @processlens.PetriNet raise {
  @processlens.PetriNet::new(
    ["p0", "p1", "p2"],
    [{ id: "ta", activity: Some("A"), }, { id: "tb", activity: Some("B"), }],
    [
      { source: "p0", target: "ta", weight: 1, },
      { source: "ta", target: "p1", weight: 1, },
      { source: "p1", target: "tb", weight: 1, },
      { source: "tb", target: "p2", weight: 1, },
    ],
    [{ place: "p0", tokens: 1, }],
    [{ place: "p2", tokens: 1, }],
  )
}

///|
fn parallel_model() -> @processlens.BpmnModel raise {
  @processlens.BpmnModel::new(
    [
      { id: "start", kind: Start, activity: None, },
      { id: "split", kind: Parallel, activity: None, },
      { id: "a", kind: Task, activity: Some("A"), },
      { id: "b", kind: Task, activity: Some("B"), },
      { id: "join", kind: Parallel, activity: None, },
      { id: "end", kind: End, activity: None, },
    ],
    [
      { id: "f0", source: "start", target: "split", },
      { id: "f1", source: "split", target: "a", },
      { id: "f2", source: "split", target: "b", },
      { id: "f3", source: "a", target: "join", },
      { id: "f4", source: "b", target: "join", },
      { id: "f5", source: "join", target: "end", },
    ],
  )
}

///|
test "ordinary Petri net captures data and checks enabled weighted execution" {
  let net = sequential_net()
  assert_eq(net.enabled(net.initial_marking()), ["ta"])
  let after = net.fire(net.initial_marking(), "ta")
  assert_eq(net.enabled(after), ["tb"])
  assert_eq(net.fire(after, "tb"), net.final_marking())
  let initial = net.initial_marking()
  initial.clear()
  let places = net.places()
  places.clear()
  assert_eq(net.initial_marking(), [1, 0, 0])
  let failed = try {
    let _ = net.fire(net.initial_marking(), "tb")
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "exact synchronous product returns minimal extra and missing activities" {
  let net = sequential_net()
  assert_eq(net_trace(["A", "B"]).align_net(net).cost, 0)
  assert_eq(net_trace(["A"]).align_net(net).cost, 1)
  assert_eq(net_trace(["X", "A", "B"]).align_net(net).cost, 1)
  assert_eq(net_trace(["B", "A"]).align_net(net).cost, 2)
  assert_eq(net_trace([]).align_net(net).cost, 2)
  let result = net_trace(["A", "B"]).align_net(net)
  assert_true(result.conforming)
  assert_eq(result.moves.length(), 2)
}

///|
test "parallel BPMN preserves both interleavings but requires both branches" {
  let model = parallel_model()
  let net = model.to_petri_net()
  assert_true(net_trace(["A", "B"]).align_net(net).conforming)
  assert_true(net_trace(["B", "A"]).align_net(net).conforming)
  assert_eq(net_trace(["A"]).align_net(net).cost, 1)
  let report = net.analyze()
  assert_true(
    report.complete &&
    report.final_reachable &&
    report.all_states_can_complete &&
    report.proper_completion,
  )
  assert_eq(report.dead_transitions, [])
}

///|
test "reachable deadlocks and dead transitions are model-level evidence" {
  let net = @processlens.PetriNet::new(
    ["p0", "p1", "sink"],
    [
      { id: "good", activity: Some("A"), },
      { id: "bad", activity: Some("B"), },
      { id: "dead", activity: Some("C"), },
    ],
    [
      { source: "p0", target: "good", weight: 1, },
      { source: "good", target: "sink", weight: 1, },
      { source: "p0", target: "bad", weight: 1, },
      { source: "bad", target: "p1", weight: 1, },
      { source: "sink", target: "dead", weight: 2, },
    ],
    [{ place: "p0", tokens: 1, }],
    [{ place: "sink", tokens: 1, }],
  )
  let report = net.analyze()
  assert_true(
    report.complete && report.final_reachable && !report.all_states_can_complete,
  )
  assert_eq(report.dead_transitions, ["dead"])
  assert_eq(report.deadlock_markings.length(), 1)
}

///|
test "unbounded generation is incomplete not a positive soundness result" {
  let net = @processlens.PetriNet::new(
    ["p"],
    [{ id: "grow", activity: None, }],
    [
      { source: "p", target: "grow", weight: 1, },
      { source: "grow", target: "p", weight: 2, },
    ],
    [{ place: "p", tokens: 1, }],
    [{ place: "p", tokens: 2, }],
  )
  let report = net.analyze(limits={
    states: 10,
    edges: 100,
    tokens_per_place: 3,
  })
  assert_true(
    !report.complete &&
    !report.all_states_can_complete &&
    !report.proper_completion,
  )
  let failed = try {
    let _ = net_trace(["X"]).align_net(net, limits={
      states: 100,
      edges: 100,
      tokens_per_place: 3,
    })
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "bounded alignment exhaustion is explicit and retry safe" {
  let net = sequential_net()
  let trace = net_trace(["A", "B"])
  let failed = try {
    let _ = trace.align_net(net, limits={
      states: 1,
      edges: 1,
      tokens_per_place: 1,
    })
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(trace.align_net(net).cost, 0)
  let log = model_log([["A", "B"], ["A", "B"]])
  let failed = try {
    let _ = log.align_net(net, limits={
      states: 1,
      edges: 1,
      tokens_per_place: 1,
    })
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "silent cycles and duplicate visible labels terminate correctly" {
  let net = @processlens.PetriNet::new(
    ["p0", "p1"],
    [
      { id: "tau", activity: None, },
      { id: "a1", activity: Some("A"), },
      { id: "a2", activity: Some("A"), },
    ],
    [
      { source: "p0", target: "tau", weight: 1, },
      { source: "tau", target: "p0", weight: 1, },
      { source: "p0", target: "a1", weight: 1, },
      { source: "a1", target: "p1", weight: 1, },
      { source: "p0", target: "a2", weight: 1, },
      { source: "a2", target: "p1", weight: 1, },
    ],
    [{ place: "p0", tokens: 1, }],
    [{ place: "p1", tokens: 1, }],
  )
  assert_eq(net_trace(["A"]).align_net(net).cost, 0)
  assert_eq(net_trace([]).align_net(net).cost, 1)
}

///|
test "classical Alpha discovers causal parallel structure not only a DFG" {
  let log = model_log([["A", "B", "C", "D"], ["A", "C", "B", "D"]])
  let net = log.discover_alpha()
  assert_eq(net.transitions().length(), 4)
  assert_eq(net.places().length(), 6)
  assert_true(net_trace(["A", "B", "C", "D"]).align_net(net).conforming)
  assert_true(net_trace(["A", "C", "B", "D"]).align_net(net).conforming)
  assert_true(!net_trace(["A", "B", "D"]).align_net(net).conforming)
  assert_true(net.analyze().all_states_can_complete)
}

///|
test "prefix net supports short loops exact observed prefixes and distinct variants" {
  let log = model_log([["A"], ["A", "B"], ["A", "A", "B", "A"]])
  let net = log.discover_prefix_net()
  for path in [["A"], ["A", "B"], ["A", "A", "B", "A"]] {
    assert_eq(net_trace(path).align_net(net).cost, 0)
  }
  for path in [[], ["B"], ["A", "B", "A"], ["A", "A", "A", "B", "A"]] {
    assert_true(net_trace(path).align_net(net).cost > 0)
  }
  let rejected = try {
    let _ = log.discover_alpha()
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "net JSON and BPMN XML expose independent public round trips" {
  let net = sequential_net()
  let restored = @processlens.parse_net(net.to_json().stringify())
  assert_eq(restored.to_json(), net.to_json())
  let model = parallel_model()
  let restored = @processlens.parse_bpmn(model.to_bpmn()).to_petri_net()
  assert_eq(net_trace(["B", "A"]).align_net(restored).cost, 0)
  let pnml = @processlens.parse_pnml(net.to_pnml())
  assert_eq(net_trace(["A", "B"]).align_net(pnml).cost, 0)
}

///|
test "model product matches independent finite-language edit distance on exhaustive words" {
  let net = parallel_model().to_petri_net()
  let refs = [
    @processlens.ReferencePath::new("AB", ["A", "B"]),
    @processlens.ReferencePath::new("BA", ["B", "A"]),
  ]
  for length in 0..<5 {
    let mut combinations = 1
    for _ in 0..<length {
      combinations *= 3
    }
    for code in 0..<combinations {
      let mut value = code
      let labels = []
      for _ in 0..<length {
        labels.push(["A", "B", "X"][value % 3])
        value /= 3
      }
      let trace = net_trace(labels)
      assert_eq(trace.align_net(net).cost, trace.align(refs).cost)
    }
  }
}
