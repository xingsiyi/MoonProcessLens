///|
priv struct AlphaPlace {
  before : Array[Int32]
  after : Array[Int32]
}

///|
fn index_union(a : Array[Int32], b : Array[Int32]) -> Array[Int32] {
  let result = a.copy()
  for item in b {
    if !result.contains(item) {
      result.push(item)
    }
  }
  result.sort_by((a, b) => a.compare(b))
  result
}

///|
/// Classical Alpha miner: one transition per activity, causal footprint and
/// maximal independent input/output sets. Explicitly rejects observed length-1
/// and length-2 loops. Incomplete/noisy logs can yield unsound or underfitting
/// nets; use analyze() and actual conformance, not a universal soundness claim.
pub fn EventLog::discover_alpha(
  self : EventLog,
  max_work~ : Int32 = 1000000,
) -> PetriNet raise ProcessError {
  model_require(
    max_work >= 1 && max_work <= 10000000,
    "alpha.work",
    "expected work budget 1..10000000",
  )
  let map = self.discover()
  let activities = map.nodes.map(node => node.activity)
  model_require(
    !activities.is_empty(),
    "alpha.log",
    "cannot discover an empty event log",
  )
  if activities.length() > 16 {
    raise Capacity(resource="alpha activities", limit=16)
  }
  let indexes : Map[String, Int32] = Map([])
  for i, name in activities {
    indexes[name] = i
  }
  let width = activities.length()
  let follows = Array::make(width * width, false)
  for edge in map.edges {
    follows[indexes[edge.source] * width + indexes[edge.target]] = true
  }
  for trace in self.traces {
    for i in 1..<trace.events.length() {
      let label = trace.events[i].activity
      model_require(
        label != trace.events[i - 1].activity,
        "alpha.log",
        "length-1 loop unsupported; use prefix-net discovery",
      )
      if i >= 2 {
        model_require(
          label != trace.events[i - 2].activity,
          "alpha.log",
          "length-2 loop unsupported; use prefix-net discovery",
        )
      }
    }
  }
  let candidates : Array[AlphaPlace] = []
  let seen : Map[String, Bool] = Map([])
  for a in 0..<width {
    for b in 0..<width {
      if follows[a * width + b] && !follows[b * width + a] {
        candidates.push({ before: [a], after: [b], })
        seen["\{1<<a}:\{1<<b}"] = true
      }
    }
  }
  let mut work = 0
  let mut head = 0
  while head < candidates.length() {
    let current = candidates[head]
    let existing = candidates.length()
    for j in 0..<existing {
      let other = candidates[j]
      let before = index_union(current.before, other.before)
      let after = index_union(current.after, other.after)
      let mut a_mask = 0
      let mut b_mask = 0
      for a in before {
        a_mask = a_mask | (1 << a)
      }
      for b in after {
        b_mask = b_mask | (1 << b)
      }
      let key = "\{a_mask}:\{b_mask}"
      if work >= max_work {
        raise Capacity(resource="alpha candidate work", limit=max_work)
      }
      work += 1
      if seen.contains(key) {
        continue
      }
      if seen.length() >= 65536 {
        raise Capacity(resource="alpha candidate identities", limit=65536)
      }
      seen[key] = true
      let mut valid = true
      for a in before {
        for b in before {
          if a != b && (follows[a * width + b] || follows[b * width + a]) {
            valid = false
          }
        }
        for b in after {
          if !follows[a * width + b] || follows[b * width + a] {
            valid = false
          }
        }
      }
      for a in after {
        for b in after {
          if a != b && (follows[a * width + b] || follows[b * width + a]) {
            valid = false
          }
        }
      }
      if valid {
        if candidates.length() >= 4096 {
          raise Capacity(resource="alpha candidates", limit=4096)
        }
        candidates.push({ before, after, })
      }
    }
    head += 1
  }
  let maximal = []
  for i, candidate in candidates {
    let mut dominated = false
    for j, other in candidates {
      if work >= max_work {
        raise Capacity(resource="alpha maximal-set work", limit=max_work)
      }
      work += 1
      if i != j &&
        candidate.before.all(a => other.before.contains(a)) &&
        candidate.after.all(b => other.after.contains(b)) {
        dominated = true
        break
      }
    }
    if !dominated {
      maximal.push(candidate)
    }
  }
  let places = ["source", "sink"]
  let transitions : Array[NetTransition] = []
  let arcs : Array[NetArc] = []
  for i, node in map.nodes {
    let id = "t\{i}"
    transitions.push({ id, activity: Some(node.activity), })
    if node.starts > 0 {
      arcs.push({ source: "source", target: id, weight: 1, })
    }
    if node.ends > 0 {
      arcs.push({ source: id, target: "sink", weight: 1, })
    }
  }
  for i, relation in maximal {
    let place = "p\{i}"
    places.push(place)
    for a in relation.before {
      arcs.push({ source: "t\{a}", target: place, weight: 1, })
    }
    for b in relation.after {
      arcs.push({ source: place, target: "t\{b}", weight: 1, })
    }
  }
  PetriNet::new(places, transitions, arcs, [{ place: "source", tokens: 1, }], [
    { place: "sink", tokens: 1, },
  ])
}

///|
/// Prefix-acceptor net discovery for exact observed finite language. Repeated
/// labels, prefixes and short loops are supported as separate occurrences; no
/// generalisation to arbitrary loop iterations or unseen concurrency is implied.
pub fn EventLog::discover_prefix_net(
  self : EventLog,
  max_nodes~ : Int32 = 4096,
) -> PetriNet raise ProcessError {
  model_require(
    max_nodes >= 2 && max_nodes <= 4096,
    "prefix.nodes",
    "expected 2..4096",
  )
  let places = ["q0", "sink"]
  let transitions : Array[NetTransition] = []
  let arcs : Array[NetArc] = []
  let edges : Map[String, String] = Map([])
  let accepting : Map[String, Bool] = Map([])
  for trace in self.traces {
    let mut current = "q0"
    for event in trace.events {
      let key = path_identity([current, event.activity])
      match edges.get(key) {
        Some(target) => current = target
        None => {
          if places.length() >= max_nodes {
            raise Capacity(resource="prefix places", limit=max_nodes)
          }
          let target = "q\{places.length()}"
          let transition = "t\{transitions.length()}"
          places.push(target)
          transitions.push({ id: transition, activity: Some(event.activity), })
          arcs.push({ source: current, target: transition, weight: 1, })
          arcs.push({ source: transition, target, weight: 1, })
          edges[key] = target
          current = target
        }
      }
    }
    accepting[current] = true
  }
  model_require(
    !self.traces.is_empty(),
    "prefix.log",
    "cannot discover an empty event log",
  )
  let terminal = accepting.keys().collect()
  terminal.sort_by((a, b) => a.lexical_compare(b))
  for place in terminal {
    let transition = "t\{transitions.length()}"
    transitions.push({ id: transition, activity: None, })
    arcs.push({ source: place, target: transition, weight: 1, })
    arcs.push({ source: transition, target: "sink", weight: 1, })
  }
  PetriNet::new(places, transitions, arcs, [{ place: "q0", tokens: 1, }], [
    { place: "sink", tokens: 1, },
  ])
}
