///|
pub(all) enum NetMove {
  Sync(event_id~ : String, transition~ : String, activity~ : String)
  LogOnly(event_id~ : String, activity~ : String)
  ModelOnly(transition~ : String, activity~ : String?)
} derive(Eq, @debug.Debug)

///|
pub extend NetMove with Eq::{equal, not_equal}

///|
pub extend NetMove with @debug.Debug::{to_repr}

///|
pub(all) struct ModelAlignment {
  case_id : String
  cost : Int32
  conforming : Bool
  moves : Array[NetMove]
  visited_states : Int32
  explored_edges : Int32
  transition_checks : Int32
  reused_variant : Bool
}

///|
priv struct SearchState {
  marking : Array[Int32]
  position : Int32
  parent : Int32?
  action : NetMove?
}

///|
priv struct SearchQueue {
  entries : Array[(Int32, Int32)]
}

///|
fn SearchQueue::push(self : SearchQueue, cost : Int32, index : Int32) -> Unit {
  self.entries.push((cost, index))
  let mut child = self.entries.length() - 1
  while child > 0 {
    let parent = (child - 1) / 2
    if self.entries[parent].0 <= cost {
      break
    }
    self.entries[child] = self.entries[parent]
    child = parent
  }
  self.entries[child] = (cost, index)
}

///|
fn SearchQueue::pop(self : SearchQueue) -> (Int32, Int32)? {
  if self.entries.is_empty() {
    return None
  }
  let result = self.entries[0]
  let last = self.entries.pop().unwrap()
  if self.entries.is_empty() {
    return Some(result)
  }
  let mut parent = 0
  while parent * 2 + 1 < self.entries.length() {
    let mut child = parent * 2 + 1
    if child + 1 < self.entries.length() &&
      self.entries[child + 1].0 < self.entries[child].0 {
      child += 1
    }
    if self.entries[child].0 >= last.0 {
      break
    }
    self.entries[parent] = self.entries[child]
    parent = child
  }
  self.entries[parent] = last
  Some(result)
}

///|
priv struct NetSearch {
  states : Array[SearchState]
  best : Map[String, (Int32, Int32)]
  queue : SearchQueue
  limits : ModelLimits
  mut edges : Int32
  mut checks : Int32
}

///|
fn NetSearch::offer(
  self : NetSearch,
  marking : Array[Int32],
  position : Int32,
  cost : Int32,
  parent : Int32,
  action : NetMove,
) -> Unit raise ProcessError {
  if self.edges >= self.limits.edges {
    raise Capacity(resource="alignment edges", limit=self.limits.edges)
  }
  self.edges += 1
  let key = marking_key(marking, position)
  if self.best.get(key) is Some((prior, _)) {
    if prior <= cost {
      return
    }
  }
  if self.states.length() >= self.limits.states {
    raise Capacity(resource="alignment states", limit=self.limits.states)
  }
  if (self.states.length() + 1).to_int64() * marking.length().to_int64() >
    4000000L {
    raise Capacity(resource="alignment marking cells", limit=4000000)
  }
  let index = self.states.length()
  self.states.push({
    marking,
    position,
    parent: Some(parent),
    action: Some(action),
  })
  self.best[key] = (cost, index)
  self.queue.push(cost, index)
}

///|
/// Dijkstra on the synchronous product (trace index, marking). Visible log/model
/// moves cost 1, sync and silent transitions cost 0. Final marking must match
/// EXACTLY. Exhaustion raises Capacity; never returns an approximate optimum.
pub fn CaseTrace::align_net(
  self : CaseTrace,
  net : PetriNet,
  limits~ : ModelLimits = ModelLimits::default(),
) -> ModelAlignment raise ProcessError {
  check_model_limits(limits)
  for tokens in net.initial {
    model_require(
      tokens <= limits.tokens_per_place,
      "initial",
      "initial marking exceeds token cap",
    )
  }
  let start : SearchState = {
    marking: net.initial.copy(),
    position: 0,
    parent: None,
    action: None,
  }
  let search : NetSearch = {
    states: [start],
    best: Map([(marking_key(start.marking, 0), (0, 0))]),
    queue: { entries: [], },
    limits,
    edges: 0,
    checks: 0,
  }
  search.queue.push(0, 0)
  while search.queue.pop() is Some((cost, index)) {
    let current = search.states[index]
    if search.best[marking_key(current.marking, current.position)].1 != index {
      continue
    }
    if current.position == self.events.length() &&
      current.marking == net.accepting {
      let moves = []
      let mut step = index
      while search.states[step].parent is Some(parent) {
        moves.push(search.states[step].action.unwrap())
        step = parent
      }
      return {
        case_id: self.id,
        cost,
        conforming: cost == 0,
        moves: moves.rev(),
        visited_states: search.states.length(),
        explored_edges: search.edges,
        transition_checks: search.checks,
        reused_variant: false,
      }
    }
    for transition in net.transitions {
      if search.checks >= limits.edges {
        raise Capacity(
          resource="alignment transition checks",
          limit=limits.edges,
        )
      }
      search.checks += 1
      if !transition.enabled(current.marking) {
        continue
      }
      let marking = transition
        .fire(current.marking, limits.tokens_per_place)
        .unwrap_or_else(() => {
          raise Capacity(
            resource="alignment tokens per place",
            limit=limits.tokens_per_place,
          )
        })
      if current.position < self.events.length() &&
        transition.activity == Some(self.events[current.position].activity) {
        let event = self.events[current.position]
        search.offer(
          marking,
          current.position + 1,
          cost,
          index,
          Sync(
            event_id=event.id,
            transition=transition.id,
            activity=event.activity,
          ),
        )
      }
      search.offer(
        marking,
        current.position,
        cost + (if transition.activity is None { 0 } else { 1 }),
        index,
        ModelOnly(transition=transition.id, activity=transition.activity),
      )
    }
    if current.position < self.events.length() {
      let event = self.events[current.position]
      search.offer(
        current.marking,
        current.position + 1,
        cost + 1,
        index,
        LogOnly(event_id=event.id, activity=event.activity),
      )
    }
  }
  raise InvalidLog(
    path="net.final",
    reason="final marking is unreachable; no complete model alignment exists",
  )
}

///|
/// Aggregate work budget bounds the whole log, including all traces, not only
/// each search. Results are returned only after all traces succeed.
pub fn EventLog::align_net(
  self : EventLog,
  net : PetriNet,
  limits~ : ModelLimits = ModelLimits::default(),
  reuse_variants~ : Bool = true,
) -> Array[ModelAlignment] raise ProcessError {
  check_model_limits(limits)
  let results = []
  let mut states = 0
  let mut edges = 0
  let variants : Map[String, ModelAlignment] = Map([])
  for trace in self.traces {
    let identity = path_identity(trace.activities())
    if reuse_variants && variants.get(identity) is Some(previous) {
      let mut position = 0
      let actions = []
      for action in previous.moves {
        match action {
          Sync(transition~, activity~, ..) => {
            actions.push(
              Sync(event_id=trace.events[position].id, transition~, activity~),
            )
            position += 1
          }
          LogOnly(activity~, ..) => {
            actions.push(LogOnly(event_id=trace.events[position].id, activity~))
            position += 1
          }
          ModelOnly(..) => actions.push(action)
        }
      }
      results.push({
        ..previous,
        case_id: trace.id,
        moves: actions,
        visited_states: 0,
        explored_edges: 0,
        transition_checks: 0,
        reused_variant: true,
      })
      continue
    }
    if states >= limits.states || edges >= limits.edges {
      raise Capacity(resource="log model alignment work", limit=limits.edges)
    }
    let result = trace.align_net(net, limits={
      ..limits,
      states: limits.states - states,
      edges: limits.edges - edges,
    })
    states += result.visited_states
    edges += result.explored_edges.max(result.transition_checks)
    if reuse_variants {
      variants[identity] = result
    }
    results.push(result)
  }
  results
}

///|
pub fn model_alignment_to_json(result : ModelAlignment) -> Json {
  let moves : Array[Json] = result.moves.map(action => {
    match action {
      Sync(event_id~, transition~, activity~) =>
        {
          "kind": "sync",
          "event_id": event_id,
          "transition": transition,
          "activity": activity,
        }
      LogOnly(event_id~, activity~) =>
        { "kind": "log", "event_id": event_id, "activity": activity }
      ModelOnly(transition~, activity~) =>
        {
          "kind": "model",
          "transition": transition,
          "activity": match activity {
            Some(v) => Json::string(v)
            None => Json::null()
          },
        }
    }
  })
  {
    "case_id": result.case_id,
    "cost": result.cost,
    "conforming": result.conforming,
    "visited_states": result.visited_states,
    "explored_edges": result.explored_edges,
    "transition_checks": result.transition_checks,
    "reused_variant": result.reused_variant,
    "moves": Json::array(moves),
  }
}
