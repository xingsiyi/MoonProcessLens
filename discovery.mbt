///|
pub(all) struct ActivityNode {
  activity : String
  occurrences : Int32
  cases : Int32
  starts : Int32
  ends : Int32
} derive(Eq, @debug.Debug)

///|
pub extend ActivityNode with Eq::{equal, not_equal}

///|
pub extend ActivityNode with @debug.Debug::{to_repr}

///|
pub(all) struct FlowEdge {
  source : String
  target : String
  occurrences : Int32
  cases : Int32
} derive(Eq, @debug.Debug)

///|
pub extend FlowEdge with Eq::{equal, not_equal}

///|
pub extend FlowEdge with @debug.Debug::{to_repr}

///|
pub(all) struct ProcessVariant {
  activities : Array[String]
  cases : Array[String]
}

///|
pub(all) struct ProcessMap {
  nodes : Array[ActivityNode]
  edges : Array[FlowEdge]
  variants : Array[ProcessVariant]
  cases : Int32
  events : Int32
}

///|
fn path_identity(activities : Array[String]) -> String {
  let result = StringBuilder()
  for value in activities {
    result.write_string("\{value.length()}:\{value}")
  }
  result.to_string()
}

///|
/// Direct-follow means adjacency in each reconstructed case, not causality.
/// Self-loops are retained; the graph does not infer a Petri net or parallelism.
pub fn EventLog::discover(self : EventLog) -> ProcessMap {
  let nodes : Map[String, ActivityNode] = Map([])
  let edges : Map[String, FlowEdge] = Map([])
  let variants : Map[String, ProcessVariant] = Map([])
  for trace in self.traces {
    let seen_nodes : Map[String, Bool] = Map([])
    let seen_edges : Map[String, Bool] = Map([])
    let names = trace.activities()
    let identity = path_identity(names)
    match variants.get(identity) {
      Some(variant) => variant.cases.push(trace.id)
      None => variants.set(identity, { activities: names, cases: [trace.id], })
    }
    for i, event in trace.events {
      let name = event.activity
      let row = nodes
        .get(name)
        .unwrap_or({
          activity: name,
          occurrences: 0,
          cases: 0,
          starts: 0,
          ends: 0,
        })
      nodes.set(name, {
        activity: name,
        occurrences: row.occurrences + 1,
        cases: row.cases + (if seen_nodes.contains(name) { 0 } else { 1 }),
        starts: row.starts + (if i == 0 { 1 } else { 0 }),
        ends: row.ends + (if i + 1 == trace.events.length() { 1 } else { 0 }),
      })
      seen_nodes.set(name, true)
      if i > 0 {
        let previous = trace.events[i - 1].activity
        let key = path_identity([previous, name])
        let edge = edges
          .get(key)
          .unwrap_or({
            source: previous,
            target: name,
            occurrences: 0,
            cases: 0,
          })
        edges.set(key, {
          ..edge,
          occurrences: edge.occurrences + 1,
          cases: edge.cases + (if seen_edges.contains(key) { 0 } else { 1 }),
        })
        seen_edges.set(key, true)
      }
    }
  }
  let sorted_nodes = nodes.values().collect()
  sorted_nodes.sort_by((a, b) => a.activity.lexical_compare(b.activity))
  let sorted_edges = edges.values().collect()
  sorted_edges.sort_by((a, b) => {
    let source = a.source.lexical_compare(b.source)
    if source != 0 {
      source
    } else {
      a.target.lexical_compare(b.target)
    }
  })
  let sorted_variants = variants.values().collect()
  sorted_variants.sort_by((a, b) => {
    let frequency = b.cases.length().compare(a.cases.length())
    if frequency != 0 {
      frequency
    } else {
      path_identity(a.activities).lexical_compare(path_identity(b.activities))
    }
  })
  {
    nodes: sorted_nodes,
    edges: sorted_edges,
    variants: sorted_variants,
    cases: self.traces.length(),
    events: self.event_count,
  }
}

///|
/// Return a detached graph filtered by edge occurrence count. All observed
/// activity nodes remain so pruning cannot silently erase isolated activities.
pub fn ProcessMap::frequent_edges(
  self : ProcessMap,
  minimum : Int32,
) -> Array[FlowEdge] raise ProcessError {
  if minimum < 1 {
    raise InvalidLog(
      path="discovery.minimum",
      reason="expected positive frequency",
    )
  }
  self.edges.filter(edge => edge.occurrences >= minimum)
}

///|
pub fn process_map_to_json(map : ProcessMap) -> Json {
  let nodes : Array[Json] = map.nodes.map(node => {
    "activity": Json::string(node.activity),
    "occurrences": Json::number(node.occurrences.to_double()),
    "cases": Json::number(node.cases.to_double()),
    "starts": Json::number(node.starts.to_double()),
    "ends": Json::number(node.ends.to_double()),
  })
  let edges : Array[Json] = map.edges.map(edge => {
    "source": Json::string(edge.source),
    "target": Json::string(edge.target),
    "occurrences": Json::number(edge.occurrences.to_double()),
    "cases": Json::number(edge.cases.to_double()),
  })
  let variants : Array[Json] = map.variants.map(variant => {
    "activities": Json::array(variant.activities.map(Json::string)),
    "cases": Json::array(variant.cases.map(Json::string)),
  })
  {
    "cases": Json::number(map.cases.to_double()),
    "events": Json::number(map.events.to_double()),
    "nodes": Json::array(nodes),
    "edges": Json::array(edges),
    "variants": Json::array(variants),
  }
}
