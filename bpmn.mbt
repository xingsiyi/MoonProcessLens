///|
pub(all) enum BpmnKind {
  Start
  End
  Task
  Exclusive
  Parallel
}

///|
pub(all) struct BpmnNode {
  id : String
  kind : BpmnKind
  activity : String?
}

///|
pub(all) struct BpmnFlow {
  id : String
  source : String
  target : String
}

///|
/// Control-flow subset with one start/end, plain tasks, exclusive and parallel
/// split/join gateways. No conditions, event semantics, subprocesses or data.
pub struct BpmnModel {
  priv nodes : Array[BpmnNode]
  priv flows : Array[BpmnFlow]
}

///|
pub fn BpmnModel::new(
  nodes : Array[BpmnNode],
  flows : Array[BpmnFlow],
) -> BpmnModel raise ProcessError {
  if nodes.length() > 4096 || flows.length() > 4096 {
    raise Capacity(resource="BPMN elements", limit=4096)
  }
  let ids : Map[String, Bool] = Map([])
  let node_ids : Map[String, Bool] = Map([])
  let mut starts = 0
  let mut ends = 0
  for node in nodes {
    process_label(node.id, "bpmn.id")
    model_require(!ids.contains(node.id), "bpmn.id", "duplicate node")
    ids[node.id] = true
    node_ids[node.id] = true
    match node.kind {
      Start => starts += 1
      End => ends += 1
      Task => {
        let label = node.activity.unwrap_or_else(() => {
          raise InvalidLog(
            path="bpmn.task",
            reason="task requires activity label",
          )
        })
        process_label(label, "bpmn.task.name")
      }
      _ => ()
    }
    if node.kind is Task {

    } else {
      model_require(
        node.activity is None,
        "bpmn.gateway",
        "non-task label must be absent",
      )
    }
  }
  model_require(
    starts == 1 && ends == 1,
    "bpmn",
    "exactly one plain start and end required",
  )
  for flow in flows {
    process_label(flow.id, "bpmn.flow.id")
    model_require(
      !ids.contains(flow.id) &&
      node_ids.contains(flow.source) &&
      node_ids.contains(flow.target),
      "bpmn.flow",
      "duplicate ID or dangling endpoint",
    )
    ids[flow.id] = true
  }
  for node in nodes {
    let incoming = flows.filter(edge => edge.target == node.id).length()
    let outgoing = flows.filter(edge => edge.source == node.id).length()
    let valid = match node.kind {
      Start => incoming == 0 && outgoing == 1
      End => incoming == 1 && outgoing == 0
      Task => incoming == 1 && outgoing == 1
      Exclusive | Parallel =>
        incoming >= 1 && outgoing >= 1 && (incoming == 1 || outgoing == 1)
    }
    model_require(
      valid, "bpmn.degree", "invalid node degree or unsupported mixed gateway/task join",
    )
  }
  { nodes: nodes.copy(), flows: flows.copy(), }
}

///|
pub fn BpmnModel::nodes(self : BpmnModel) -> Array[BpmnNode] {
  self.nodes.copy()
}

///|
pub fn BpmnModel::flows(self : BpmnModel) -> Array[BpmnFlow] {
  self.flows.copy()
}

///|
pub fn BpmnModel::to_petri_net(self : BpmnModel) -> PetriNet raise ProcessError {
  let places = ["source", "sink"]
  let flow_places : Map[String, String] = Map([])
  for i, flow in self.flows {
    let name = "f\{i}"
    places.push(name)
    flow_places[flow.id] = name
  }
  let transitions : Array[NetTransition] = []
  let arcs : Array[NetArc] = []
  for node in self.nodes {
    let incoming = self.flows
      .filter(flow => flow.target == node.id)
      .map(flow => flow_places[flow.id])
    let outgoing = self.flows
      .filter(flow => flow.source == node.id)
      .map(flow => flow_places[flow.id])
    match node.kind {
      Exclusive =>
        for input in incoming {
          for output in outgoing {
            let id = "t\{transitions.length()}"
            transitions.push({ id, activity: None, })
            arcs.push({ source: input, target: id, weight: 1, })
            arcs.push({ source: id, target: output, weight: 1, })
          }
        }
      _ => {
        let id = "t\{transitions.length()}"
        transitions.push({ id, activity: node.activity, })
        for source in (if node.kind is Start { ["source"] } else { incoming }) {
          arcs.push({ source, target: id, weight: 1, })
        }
        for target in (if node.kind is End { ["sink"] } else { outgoing }) {
          arcs.push({ source: id, target, weight: 1, })
        }
      }
    }
  }
  PetriNet::new(places, transitions, arcs, [{ place: "source", tokens: 1, }], [
    { place: "sink", tokens: 1, },
  ])
}

///|
fn bpmn_children(node : ModelXml) -> Unit raise ProcessError {
  for item in node.children {
    model_require(
      item.ns == node.ns &&
      ["documentation", "incoming", "outgoing"].contains(item.name) &&
      item.children.is_empty(),
      "bpmn.node",
      "event definitions, subprocesses and execution extensions unsupported",
    )
  }
}

///|
pub fn parse_bpmn(text : String) -> BpmnModel raise ProcessError {
  let root = model_xml(text)
  let ns = "http://www.omg.org/spec/BPMN/20100524/MODEL"
  model_require(
    root.name == "definitions" && root.ns == ns,
    "bpmn",
    "expected BPMN 2.0 definitions namespace",
  )
  let processes = root.children.filter(child => {
    child.name == "process" && child.ns == ns
  })
  model_require(processes.length() == 1, "bpmn", "one process required")
  for child in root.children {
    model_require(
      (child.ns == ns && child.name == "process") ||
      (
        child.ns == "http://www.omg.org/spec/BPMN/20100524/DI" &&
        child.name == "BPMNDiagram"
      ),
      "bpmn.definitions",
      "unsupported definitions semantics",
    )
  }
  let process = processes[0]
  process.only_attributes(["id", "name", "isExecutable"])
  model_require(
    process.attributes.get("isExecutable").unwrap_or("false") == "false",
    "bpmn",
    "executable process semantics unsupported",
  )
  let nodes : Array[BpmnNode] = []
  let flows : Array[BpmnFlow] = []
  for child in process.children {
    model_require(child.ns == ns, "bpmn", "foreign process extension")
    if child.name == "documentation" {
      continue
    }
    if child.name == "sequenceFlow" {
      child.only_attributes(["id", "name", "sourceRef", "targetRef"])
      model_require(
        child.children.all(item => item.name == "documentation" && item.ns == ns),
        "bpmn.flow",
        "conditional/default execution unsupported",
      )
      model_require(
        !child.attributes.contains("isImmediate"),
        "bpmn.flow",
        "execution attribute unsupported",
      )
      flows.push({
        id: child.attribute("id"),
        source: child.attribute("sourceRef"),
        target: child.attribute("targetRef"),
      })
      continue
    }
    bpmn_children(child)
    child.only_attributes(["id", "name", "gatewayDirection"])
    model_require(
      !child.attributes.contains("default") &&
      !child.attributes.contains("isForCompensation"),
      "bpmn.node",
      "default/compensation semantics unsupported",
    )
    let kind = match child.name {
      "startEvent" => Start
      "endEvent" => End
      "task" => Task
      "exclusiveGateway" => Exclusive
      "parallelGateway" => Parallel
      _ =>
        raise InvalidLog(
          path="bpmn.node",
          reason="unsupported BPMN node: \{child.name}",
        )
    }
    nodes.push({
      id: child.attribute("id"),
      kind,
      activity: if kind is Task {
        Some(child.attribute("name"))
      } else {
        None
      },
    })
  }
  let result = BpmnModel::new(nodes, flows)
  // Redundant incoming/outgoing XML must agree with sequenceFlow endpoints.
  for node in process.children {
    if node.name == "sequenceFlow" || node.name == "documentation" {
      continue
    }
    for child in node.children {
      if child.name == "incoming" || child.name == "outgoing" {
        let candidates = flows.filter(flow => {
          flow.id == child.text.trim().to_owned()
        })
        model_require(
          candidates.length() == 1,
          "bpmn.flowRef",
          "unknown flow reference",
        )
        model_require(
          if child.name == "incoming" {
            candidates[0].target == node.attribute("id")
          } else {
            candidates[0].source == node.attribute("id")
          },
          "bpmn.flowRef",
          "flow endpoint mismatch",
        )
      }
    }
  }
  result
}

///|
pub fn BpmnModel::to_bpmn(self : BpmnModel) -> String {
  let out = StringBuilder()
  let xml_ids : Map[String, String] = Map([])
  for i, node in self.nodes {
    xml_ids[node.id] = "n\{i}"
  }
  out.write_string(
    "<?xml version=\"1.0\"?><definitions xmlns=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" targetNamespace=\"urn:moonprocesslens\"><process id=\"ProcessLens\" isExecutable=\"false\">",
  )
  for node in self.nodes {
    let tag = match node.kind {
      Start => "startEvent"
      End => "endEvent"
      Task => "task"
      Exclusive => "exclusiveGateway"
      Parallel => "parallelGateway"
    }
    out.write_string("<\{tag} id=\"\{xml_ids[node.id]}\"")
    if node.activity is Some(activity) {
      out.write_string(" name=\"\{xml_escape(activity)}\"")
    }
    out.write_string("/>")
  }
  for i, flow in self.flows {
    out.write_string(
      "<sequenceFlow id=\"e\{i}\" sourceRef=\"\{xml_ids[flow.source]}\" targetRef=\"\{xml_ids[flow.target]}\"/>",
    )
  }
  out.write_string("</process></definitions>")
  out.to_string()
}
