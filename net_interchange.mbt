///|
pub fn PetriNet::to_json(self : PetriNet) -> Json {
  let transitions : Array[Json] = self.transitions.map(t => {
    "id": t.id,
    "activity": match t.activity {
      Some(v) => Json::string(v)
      None => Json::null()
    },
  })
  let arcs : Array[Json] = self
    .arcs()
    .map(a => { "source": a.source, "target": a.target, "weight": a.weight })
  let initial : Array[Json] = self.initial.map(n => Json::number(n.to_double()))
  let accepting : Array[Json] = self.accepting.map(n => {
    Json::number(n.to_double())
  })
  {
    "places": Json::array(self.places.map(Json::string)),
    "transitions": Json::array(transitions),
    "arcs": Json::array(arcs),
    "initial": Json::array(initial),
    "final": Json::array(accepting),
  }
}

///|
fn net_integer(value : Json, minimum : Int32) -> Int32 raise ProcessError {
  match value {
    Number(n, ..) if !n.is_nan() &&
      !n.is_inf() &&
      n >= minimum.to_double() &&
      n <= 1000000.0 &&
      n.to_int().to_double() == n => n.to_int()
    _ =>
      raise InvalidLog(
        path="net.number",
        reason="expected bounded token/weight integer",
      )
  }
}

///|
pub fn parse_net(text : String) -> PetriNet raise ProcessError {
  let fields = process_object(
    parse_process_json(text),
    ["places", "transitions", "arcs", "initial", "final"],
    "net",
  )
  let places = []
  for item in process_array(process_required(fields, "places"), "places") {
    places.push(process_string(item, "place"))
  }
  let transitions = []
  for
    value in process_array(
      process_required(fields, "transitions"),
      "transitions",
    ) {
    let row = process_object(value, ["id", "activity"], "transition")
    let activity = match process_required(row, "activity") {
      Null => None
      value => Some(process_string(value, "activity"))
    }
    transitions.push({
      id: process_string(process_required(row, "id"), "id"),
      activity,
    })
  }
  let arcs = []
  for value in process_array(process_required(fields, "arcs"), "arcs") {
    let row = process_object(value, ["source", "target", "weight"], "arc")
    arcs.push({
      source: process_string(process_required(row, "source"), "source"),
      target: process_string(process_required(row, "target"), "target"),
      weight: net_integer(process_required(row, "weight"), 1),
    })
  }
  let initial = process_array(process_required(fields, "initial"), "initial")
  let accepting = process_array(process_required(fields, "final"), "final")
  model_require(
    initial.length() == places.length() && accepting.length() == places.length(),
    "marking",
    "wrong marking dimension",
  )
  let first = []
  let last = []
  for i, place in places {
    first.push({ place, tokens: net_integer(initial[i], 0), })
    last.push({ place, tokens: net_integer(accepting[i], 0), })
  }
  PetriNet::new(places, transitions, arcs, first, last)
}

///|
pub fn PetriNet::to_pnml(self : PetriNet) -> String {
  let out = StringBuilder()
  let xml_ids : Map[String, String] = Map([])
  for i, place in self.places {
    xml_ids[place] = "p\{i}"
  }
  for i, t in self.transitions {
    xml_ids[t.id] = "t\{i}"
  }
  out.write_string(
    "<?xml version=\"1.0\"?><pnml><net id=\"ProcessLens\" type=\"http://www.pnml.org/version-2009/grammar/ptnet\"><page id=\"page0\">",
  )
  for i, place in self.places {
    out.write_string(
      "<place id=\"\{xml_ids[place]}\"><name><text>\{xml_escape(place)}</text></name>",
    )
    if self.initial[i] > 0 {
      out.write_string(
        "<initialMarking><text>\{self.initial[i]}</text></initialMarking>",
      )
    }
    out.write_string("</place>")
  }
  for t in self.transitions {
    out.write_string(
      "<transition id=\"\{xml_ids[t.id]}\"><name><text>\{xml_escape(t.activity.unwrap_or(t.id))}</text></name>",
    )
    if t.activity is None {
      out.write_string(
        "<toolspecific tool=\"ProM\" version=\"6.4\" activity=\"$invisible$\"/>",
      )
    }
    out.write_string("</transition>")
  }
  for i, arc in self.arcs() {
    out.write_string(
      "<arc id=\"a\{i}\" source=\"\{xml_ids[arc.source]}\" target=\"\{xml_ids[arc.target]}\"><inscription><text>\{arc.weight}</text></inscription></arc>",
    )
  }
  out.write_string("</page><finalmarkings><marking>")
  for i, tokens in self.accepting {
    if tokens > 0 {
      out.write_string(
        "<place idref=\"\{xml_ids[self.places[i]]}\"><text>\{tokens}</text></place>",
      )
    }
  }
  out.write_string("</marking></finalmarkings></net></pnml>")
  out.to_string()
}

///|
pub fn model_analysis_to_json(report : ModelAnalysis) -> Json {
  {
    "complete": report.complete,
    "states": report.states,
    "edges": report.edges,
    "final_reachable": report.final_reachable,
    "all_states_can_complete": report.all_states_can_complete,
    "proper_completion": report.proper_completion,
    "dead_transitions": Json::array(report.dead_transitions.map(Json::string)),
    "deadlock_markings": Json::array(
      report.deadlock_markings.map(marking => {
        Json::array(marking.map(n => Json::number(n.to_double())))
      }),
    ),
  }
}
