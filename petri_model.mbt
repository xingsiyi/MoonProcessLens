///|
pub(all) struct NetTransition {
  id : String
  activity : String?
}

///|
pub(all) struct NetArc {
  source : String
  target : String
  weight : Int32
}

///|
pub(all) struct PlaceTokens {
  place : String
  tokens : Int32
}

///|
priv struct CompiledTransition {
  id : String
  activity : String?
  inputs : Array[(Int32, Int32)]
  outputs : Array[(Int32, Int32)]
}

///|
/// Ordinary weighted P/T net; no inhibitors, priorities or coloured tokens.
/// Captures all arrays. Markings are vectors in places() order.
pub struct PetriNet {
  priv places : Array[String]
  priv transitions : Array[CompiledTransition]
  priv initial : Array[Int32]
  priv accepting : Array[Int32]
}

///|
fn model_require(
  condition : Bool,
  path : String,
  reason : String,
) -> Unit raise ProcessError {
  if !condition {
    raise InvalidLog(path~, reason~)
  }
}

///|
fn net_marking(
  places : Map[String, Int32],
  values : Array[PlaceTokens],
) -> Array[Int32] raise ProcessError {
  let result = Array::make(places.length(), 0)
  let seen : Map[String, Bool] = Map([])
  for item in values {
    model_require(!seen.contains(item.place), "marking", "duplicate place")
    let index = places
      .get(item.place)
      .unwrap_or_else(() => {
        raise InvalidLog(path="marking", reason="unknown place")
      })
    model_require(
      item.tokens >= 0 && item.tokens <= 1000000,
      "marking",
      "token count outside 0..1000000",
    )
    seen[item.place] = true
    result[index] = item.tokens
  }
  result
}

///|
pub fn PetriNet::new(
  places : Array[String],
  transitions : Array[NetTransition],
  arcs : Array[NetArc],
  initial : Array[PlaceTokens],
  accepting : Array[PlaceTokens],
) -> PetriNet raise ProcessError {
  model_require(!places.is_empty(), "net.places", "at least one place required")
  if places.length() > 4096 ||
    transitions.length() > 8192 ||
    arcs.length() > 65536 {
    raise Capacity(resource="net elements", limit=65536)
  }
  let place_ids : Map[String, Int32] = Map([])
  let transition_ids : Map[String, Int32] = Map([])
  for i, id in places {
    process_label(id, "place.id")
    model_require(!place_ids.contains(id), "place.id", "duplicate place")
    place_ids[id] = i
  }
  let compiled : Array[CompiledTransition] = []
  for i, transition in transitions {
    process_label(transition.id, "transition.id")
    model_require(
      !place_ids.contains(transition.id) &&
      !transition_ids.contains(transition.id),
      "transition.id",
      "duplicate node identity",
    )
    if transition.activity is Some(activity) {
      process_label(activity, "transition.activity")
    }
    transition_ids[transition.id] = i
    compiled.push({
      id: transition.id,
      activity: transition.activity,
      inputs: [],
      outputs: [],
    })
  }
  let seen : Map[String, Bool] = Map([])
  for arc in arcs {
    model_require(
      arc.weight >= 1 && arc.weight <= 1000000,
      "arc.weight",
      "expected 1..1000000",
    )
    let key = path_identity([arc.source, arc.target])
    model_require(
      !seen.contains(key),
      "arc",
      "duplicate arc; use a single weight",
    )
    seen[key] = true
    match
      (
        place_ids.get(arc.source),
        transition_ids.get(arc.target),
        transition_ids.get(arc.source),
        place_ids.get(arc.target),
      ) {
      (Some(p), Some(t), None, None) => compiled[t].inputs.push((p, arc.weight))
      (None, None, Some(t), Some(p)) =>
        compiled[t].outputs.push((p, arc.weight))
      _ =>
        raise InvalidLog(
          path="arc",
          reason="arc must connect an existing place and transition",
        )
    }
  }
  {
    places: places.copy(),
    transitions: compiled,
    initial: net_marking(place_ids, initial),
    accepting: net_marking(place_ids, accepting),
  }
}

///|
pub fn PetriNet::places(self : PetriNet) -> Array[String] {
  self.places.copy()
}

///|
pub fn PetriNet::transitions(self : PetriNet) -> Array[NetTransition] {
  self.transitions.map(item => { id: item.id, activity: item.activity, })
}

///|
pub fn PetriNet::arcs(self : PetriNet) -> Array[NetArc] {
  let result = []
  for t in self.transitions {
    for input in t.inputs {
      result.push({
        source: self.places[input.0],
        target: t.id,
        weight: input.1,
      })
    }
    for output in t.outputs {
      result.push({
        source: t.id,
        target: self.places[output.0],
        weight: output.1,
      })
    }
  }
  result
}

///|
pub fn PetriNet::initial_marking(self : PetriNet) -> Array[Int32] {
  self.initial.copy()
}

///|
pub fn PetriNet::final_marking(self : PetriNet) -> Array[Int32] {
  self.accepting.copy()
}

///|
fn PetriNet::check_marking(
  self : PetriNet,
  marking : Array[Int32],
) -> Unit raise ProcessError {
  model_require(
    marking.length() == self.places.length(),
    "marking",
    "wrong marking dimension",
  )
  for tokens in marking {
    model_require(
      tokens >= 0 && tokens <= 1000000,
      "marking",
      "token count outside range",
    )
  }
}

///|
fn CompiledTransition::enabled(
  self : CompiledTransition,
  marking : Array[Int32],
) -> Bool {
  self.inputs.all(item => marking[item.0] >= item.1)
}

///|
// None is a capacity boundary, never a disabled transition.
fn CompiledTransition::fire(
  self : CompiledTransition,
  marking : Array[Int32],
  cap : Int32,
) -> Array[Int32]? {
  let result = marking.copy()
  for item in self.inputs {
    result[item.0] -= item.1
  }
  for item in self.outputs {
    if item.1 > cap - result[item.0] {
      return None
    }
    result[item.0] += item.1
  }
  Some(result)
}

///|
pub fn PetriNet::enabled(
  self : PetriNet,
  marking : Array[Int32],
) -> Array[String] raise ProcessError {
  self.check_marking(marking)
  self.transitions.filter(item => item.enabled(marking)).map(item => item.id)
}

///|
pub fn PetriNet::fire(
  self : PetriNet,
  marking : Array[Int32],
  transition : String,
) -> Array[Int32] raise ProcessError {
  self.check_marking(marking)
  let choices = self.transitions.filter(item => item.id == transition)
  model_require(choices.length() == 1, "transition", "unknown transition")
  model_require(
    choices[0].enabled(marking),
    "transition",
    "transition is not enabled",
  )
  choices[0]
  .fire(marking, 1000000)
  .unwrap_or_else(() => raise Capacity(resource="place tokens", limit=1000000))
}

///|
fn marking_key(marking : Array[Int32], position : Int32) -> String {
  let out = StringBuilder()
  out.write_string("\{position}:")
  for tokens in marking {
    out.write_string("\{tokens},")
  }
  out.to_string()
}

///|
pub(all) struct ModelLimits {
  states : Int32
  edges : Int32
  tokens_per_place : Int32
}

///|
pub fn ModelLimits::default() -> ModelLimits {
  { states: 20000, edges: 200000, tokens_per_place: 64, }
}

///|
fn check_model_limits(limits : ModelLimits) -> Unit raise ProcessError {
  model_require(
    limits.states >= 1 &&
    limits.states <= 200000 &&
    limits.edges >= 1 &&
    limits.edges <= 2000000 &&
    limits.tokens_per_place >= 1 &&
    limits.tokens_per_place <= 1000000,
    "model.limits",
    "invalid exploration limits",
  )
}

///|
pub(all) struct ModelAnalysis {
  complete : Bool
  states : Int32
  edges : Int32
  final_reachable : Bool
  all_states_can_complete : Bool
  proper_completion : Bool
  dead_transitions : Array[String]
  deadlock_markings : Array[Array[Int32]]
}

///|
/// These are accepting-net behavioural checks, NOT a full WF-net structural
/// soundness theorem. Positive conclusions require complete exploration.
pub fn PetriNet::analyze(
  self : PetriNet,
  limits~ : ModelLimits = ModelLimits::default(),
) -> ModelAnalysis raise ProcessError {
  check_model_limits(limits)
  for item in self.initial {
    model_require(
      item <= limits.tokens_per_place,
      "initial",
      "initial tokens exceed exploration cap",
    )
  }
  let states = [self.initial.copy()]
  let indexes : Map[String, Int32] = Map([(marking_key(self.initial, 0), 0)])
  let reverse : Array[Array[Int32]] = [[]]
  let live : Map[String, Bool] = Map([])
  let deadlocks = []
  let mut count_edges = 0
  let mut checks = 0
  let mut head = 0
  let mut complete = true
  let mut proper = true
  let mut stopped = false
  while head < states.length() {
    let marking = states[head]
    let mut any_enabled = false
    let mut covers_final = marking != self.accepting &&
      self.accepting.any(n => n > 0)
    for i, tokens in self.accepting {
      if marking[i] < tokens {
        covers_final = false
      }
    }
    if covers_final {
      proper = false
    }
    for transition in self.transitions {
      if checks >= limits.edges {
        complete = false
        stopped = true
        break
      }
      checks += 1
      if !transition.enabled(marking) {
        continue
      }
      any_enabled = true
      if count_edges >= limits.edges {
        complete = false
        continue
      }
      match transition.fire(marking, limits.tokens_per_place) {
        None => complete = false
        Some(next) => {
          let key = marking_key(next, 0)
          let target = match indexes.get(key) {
            Some(index) => Some(index)
            None =>
              if states.length() >= limits.states ||
                (states.length() + 1).to_int64() *
                self.places.length().to_int64() >
                4000000L {
                complete = false
                None
              } else {
                let index = states.length()
                states.push(next)
                reverse.push([])
                indexes[key] = index
                Some(index)
              }
          }
          if target is Some(target) {
            reverse[target].push(head)
            live[transition.id] = true
            count_edges += 1
          }
        }
      }
    }
    if stopped {
      break
    }
    if !any_enabled && marking != self.accepting {
      deadlocks.push(marking.copy())
    }
    head += 1
  }
  let final_index = indexes.get(marking_key(self.accepting, 0))
  let reached : Map[Int32, Bool] = Map([])
  let queue = []
  if final_index is Some(index) {
    reached[index] = true
    queue.push(index)
  }
  let mut head = 0
  while head < queue.length() {
    for source in reverse[queue[head]] {
      if !reached.contains(source) {
        reached[source] = true
        queue.push(source)
      }
    }
    head += 1
  }
  {
    complete,
    states: states.length(),
    edges: count_edges,
    final_reachable: final_index is Some(_),
    all_states_can_complete: complete && reached.length() == states.length(),
    proper_completion: complete && proper,
    dead_transitions: self.transitions
    .filter(t => !live.contains(t.id))
    .map(t => t.id),
    deadlock_markings: deadlocks,
  }
}
