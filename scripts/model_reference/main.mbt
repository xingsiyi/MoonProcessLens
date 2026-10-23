///|
fn trace(labels : Array[String]) -> @lens.CaseTrace raise {
  let events = []
  for i, label in labels {
    events.push(
      @lens.LogEvent::new(
        "e\{i}",
        "reference",
        label,
        i.to_int64() * 10L,
        i.to_int64() * 10L + 1L,
      ),
    )
  }
  @lens.CaseTrace::new("reference", events)
}

///|
fn parallel() -> @lens.BpmnModel raise {
  @lens.BpmnModel::new(
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
fn probe(
  name : String,
  net : @lens.PetriNet,
  maximum_length : Int32,
) -> Unit raise {
  let observations : Array[Json] = []
  for length in 0..<(maximum_length + 1) {
    let mut count = 1
    for _ in 0..<length {
      count *= 3
    }
    for i in 0..<count {
      let labels = []
      let mut code = i
      for _ in 0..<length {
        labels.push(["A", "B", "X"][code % 3])
        code /= 3
      }
      let result = trace(labels).align_net(net)
      observations.push({
        "trace": Json::array(labels.map(Json::string)),
        "cost": result.cost,
      })
    }
  }
  let row : Json = {
    "kind": if name == "weighted" {
      "weighted"
    } else {
      "alignment"
    },
    "name": name,
    "net": net.to_json(),
    "observations": Json::array(observations),
  }
  println(row.stringify())
}

///|
fn main raise {
  let sequence = @lens.PetriNet::new(
    ["p0", "p1", "p2"],
    [{ id: "a", activity: Some("A"), }, { id: "b", activity: Some("B"), }],
    [
      { source: "p0", target: "a", weight: 1, },
      { source: "a", target: "p1", weight: 1, },
      { source: "p1", target: "b", weight: 1, },
      { source: "b", target: "p2", weight: 1, },
    ],
    [{ place: "p0", tokens: 1, }],
    [{ place: "p2", tokens: 1, }],
  )
  probe("sequence", sequence, 4)
  let bpmn = parallel()
  probe("BPMN_parallel", bpmn.to_petri_net(), 4)
  let exclusive = @lens.PetriNet::new(
    ["p0", "sink"],
    [{ id: "a", activity: Some("A"), }, { id: "b", activity: Some("B"), }],
    [
      { source: "p0", target: "a", weight: 1, },
      { source: "a", target: "sink", weight: 1, },
      { source: "p0", target: "b", weight: 1, },
      { source: "b", target: "sink", weight: 1, },
    ],
    [{ place: "p0", tokens: 1, }],
    [{ place: "sink", tokens: 1, }],
  )
  probe("exclusive", exclusive, 4)
  let looping = @lens.PetriNet::new(
    ["p0", "sink"],
    [{ id: "a", activity: Some("A"), }, { id: "b", activity: Some("B"), }],
    [
      { source: "p0", target: "a", weight: 1, },
      { source: "a", target: "p0", weight: 1, },
      { source: "p0", target: "b", weight: 1, },
      { source: "b", target: "sink", weight: 1, },
    ],
    [{ place: "p0", tokens: 1, }],
    [{ place: "sink", tokens: 1, }],
  )
  probe("loop", looping, 4)
  let weighted = @lens.PetriNet::new(
    ["p0", "p1", "sink"],
    [{ id: "a", activity: Some("A"), }, { id: "b", activity: Some("B"), }],
    [
      { source: "p0", target: "a", weight: 1, },
      { source: "a", target: "p1", weight: 1, },
      { source: "p1", target: "b", weight: 2, },
      { source: "b", target: "sink", weight: 1, },
    ],
    [{ place: "p0", tokens: 2, }],
    [{ place: "sink", tokens: 1, }],
  )
  probe("weighted", weighted, 4)
  let paths = [["A", "B", "C", "D"], ["A", "C", "B", "D"]]
  let events = []
  for c, labels in paths {
    for i, label in labels {
      events.push(
        @lens.LogEvent::new(
          "e\{c}-\{i}",
          "c\{c}",
          label,
          i.to_int64() * 10L,
          i.to_int64() * 10L + 1L,
        ),
      )
    }
  }
  let log = @lens.EventLog::new(events)
  let alpha = log.discover_alpha()
  let samples = [
    ["A", "B", "C", "D"],
    ["A", "C", "B", "D"],
    ["A", "B", "D"],
    ["A", "C", "D"],
    [],
    ["D", "A"],
  ]
  let observations : Array[Json] = []
  for path in samples {
    observations.push({
      "trace": Json::array(path.map(Json::string)),
      "cost": trace(path).align_net(alpha).cost,
    })
  }
  let discovery : Json = {
    "kind": "alpha",
    "training": paths,
    "net": alpha.to_json(),
    "observations": Json::array(observations),
  }
  println(discovery.stringify())
  let exchange : Json = {
    "kind": "interchange",
    "xes": log.to_xes(),
    "pnml": alpha.to_pnml(),
    "bpmn": bpmn.to_bpmn(),
    "bpmn_expected": [
      { "trace": ["A", "B"], "cost": 0 },
      { "trace": ["B", "A"], "cost": 0 },
      { "trace": ["A"], "cost": 1 },
    ],
  }
  println(exchange.stringify())
}
