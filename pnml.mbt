///|
fn pnml_child(node : ModelXml, name : String) -> ModelXml? raise ProcessError {
  let children = node.children.filter(item => {
    item.ns == node.ns && item.name == name
  })
  model_require(children.length() <= 1, "pnml", "duplicate \{name}")
  if children.is_empty() {
    None
  } else {
    Some(children[0])
  }
}

///|
fn pnml_text(node : ModelXml) -> String raise ProcessError {
  let text = pnml_child(node, "text").unwrap_or_else(() => {
    raise InvalidLog(path="pnml.text", reason="missing text")
  })
  model_require(
    text.children.is_empty(),
    "pnml.text",
    "nested text unsupported",
  )
  text.text.trim().to_owned()
}

///|
fn pnml_count(text : String, minimum : Int32) -> Int32 raise ProcessError {
  model_require(
    text.length() > 0 && text.length() <= 7,
    "pnml.count",
    "invalid token/weight count",
  )
  let mut value = 0
  for ch in text {
    let n = ch.to_int() - 48
    model_require(n >= 0 && n <= 9, "pnml.count", "expected unsigned decimal")
    value = value * 10 + n
  }
  model_require(
    value >= minimum && value <= 1000000,
    "pnml.count",
    "count outside supported range",
  )
  value
}

///|
/// Single net, one flat page (or direct nodes), ordinary weighted PNML P/T net.
/// Requires explicit finalmarkings; never guesses accepting semantics from a
/// sink. ProM $invisible$ is recognized, other executable annotations refused.
pub fn parse_pnml(text : String) -> PetriNet raise ProcessError {
  let root = model_xml(text)
  model_require(
    root.name == "pnml" &&
    ["", "http://www.pnml.org/version-2009/grammar/pnml"].contains(root.ns),
    "pnml",
    "unsupported PNML namespace",
  )
  model_require(
    root.children.length() == 1 &&
    root.children[0].name == "net" &&
    root.children[0].ns == root.ns,
    "pnml",
    "exactly one net required",
  )
  let net = root.children[0]
  net.only_attributes(["id", "type"])
  model_require(
    [
      "http://www.pnml.org/version-2009/grammar/ptnet", "http://www.pnml.org/version-2009/grammar/pnmlcoremodel",
    ].contains(net.attribute("type")),
    "pnml.type",
    "only ordinary P/T/coremodel transport supported",
  )
  let page = pnml_child(net, "page")
  let elements = match page {
    Some(page) => {
      page.only_attributes(["id"])
      page.children
    }
    None =>
      net.children.filter(item => {
        item.name != "finalmarkings" && item.name != "name"
      })
  }
  if page is Some(_) {
    model_require(
      net.children.all(item => {
        ["page", "name", "finalmarkings"].contains(item.name)
      }),
      "pnml.net",
      "unsupported net semantics",
    )
  }
  let places = []
  let transitions : Array[NetTransition] = []
  let arcs : Array[NetArc] = []
  let initial : Array[PlaceTokens] = []
  let accepting : Array[PlaceTokens] = []
  let arc_ids : Map[String, Bool] = Map([])
  for item in elements {
    model_require(item.ns == root.ns, "pnml.namespace", "mixed namespace")
    if ["name", "graphics"].contains(item.name) {
      continue
    }
    if item.name == "place" {
      item.only_attributes(["id"])
      let id = item.attribute("id")
      places.push(id)
      model_require(
        item.children.all(child => {
          ["name", "initialMarking", "graphics"].contains(child.name)
        }),
        "pnml.place",
        "unsupported place annotation",
      )
      if pnml_child(item, "initialMarking") is Some(marking) {
        initial.push({ place: id, tokens: pnml_count(pnml_text(marking), 0), })
      }
    } else if item.name == "transition" {
      item.only_attributes(["id"])
      let id = item.attribute("id")
      let mut activity = match pnml_child(item, "name") {
        Some(name) => Some(pnml_text(name))
        None => Some(id)
      }
      for child in item.children {
        model_require(
          ["name", "graphics", "toolspecific"].contains(child.name),
          "pnml.transition",
          "unsupported transition annotation",
        )
        if child.name == "toolspecific" {
          model_require(
            child.attributes.get("tool") == Some("ProM") &&
            child.attributes.get("activity") == Some("$invisible$") &&
            child.children.is_empty(),
            "pnml.toolspecific",
            "only explicit ProM silent marker supported",
          )
          activity = None
        }
      }
      transitions.push({ id, activity, })
    } else if item.name == "arc" {
      item.only_attributes(["id", "source", "target"])
      let id = item.attribute("id")
      model_require(!arc_ids.contains(id), "pnml.arc", "duplicate arc ID")
      arc_ids[id] = true
      model_require(
        item.children.all(child => {
          ["inscription", "graphics", "name"].contains(child.name)
        }),
        "pnml.arc",
        "inhibitor/reset/other arc extensions unsupported",
      )
      let weight = match pnml_child(item, "inscription") {
        Some(count) => pnml_count(pnml_text(count), 1)
        None => 1
      }
      arcs.push({
        source: item.attribute("source"),
        target: item.attribute("target"),
        weight,
      })
    } else {
      raise InvalidLog(path="pnml.page", reason="unsupported PNML element")
    }
  }
  for id in places {
    model_require(
      !arc_ids.contains(id),
      "pnml.id",
      "node/arc identity collision",
    )
  }
  for t in transitions {
    model_require(
      !arc_ids.contains(t.id),
      "pnml.id",
      "node/arc identity collision",
    )
  }
  let final_markings = pnml_child(net, "finalmarkings").unwrap_or_else(() => {
    raise InvalidLog(
      path="pnml.final",
      reason="explicit final marking required",
    )
  })
  model_require(
    final_markings.children.length() == 1 &&
    final_markings.children[0].name == "marking",
    "pnml.final",
    "one accepting marking required",
  )
  for place in final_markings.children[0].children {
    model_require(
      place.name == "place" && place.ns == root.ns,
      "pnml.final",
      "expected place reference",
    )
    accepting.push({
      place: place.attribute("idref"),
      tokens: pnml_count(pnml_text(place), 0),
    })
  }
  PetriNet::new(places, transitions, arcs, initial, accepting)
}
