///|
priv struct ModelXml {
  name : String
  ns : String
  attributes : Map[String, String]
  children : Array[ModelXml]
  text : String
}

///|
priv struct XmlCursor {
  source : String
  mut offset : Int32
  mut nodes : Int32
}

///|
fn XmlCursor::at(self : XmlCursor, token : String) -> Bool {
  if token.length() > self.source.length() - self.offset {
    return false
  }
  // Raw code-unit comparison: a StringView beginning at a low surrogate may
  // advance to the next scalar and falsely match the quote after a non-BMP char.
  for i in 0..<token.length() {
    if self.source.code_unit_at(self.offset + i) != token.code_unit_at(i) {
      return false
    }
  }
  true
}

///|
fn XmlCursor::take(self : XmlCursor, token : String) -> Unit raise ProcessError {
  model_require(self.at(token), "xml", "expected \{token} at \{self.offset}")
  self.offset += token.length()
}

///|
fn xml_space(unit : Int32) -> Bool {
  unit == 32 || unit == 9 || unit == 10 || unit == 13
}

///|
fn XmlCursor::space(self : XmlCursor) -> Unit {
  while self.offset < self.source.length() &&
        xml_space(self.source.code_unit_at(self.offset).to_int()) {
    self.offset += 1
  }
}

///|
fn XmlCursor::misc(self : XmlCursor) -> Unit raise ProcessError {
  self.space()
  while self.at("<!--") {
    self.offset += 4
    let value = self.until("-->")
    model_require(
      !value.contains("--") && !value.has_suffix("-"),
      "xml.comment",
      "invalid comment",
    )
    self.space()
  }
}

///|
fn XmlCursor::until(
  self : XmlCursor,
  token : String,
) -> String raise ProcessError {
  let start = self.offset
  while self.offset < self.source.length() && !self.at(token) {
    self.offset += 1
  }
  model_require(
    self.offset < self.source.length(),
    "xml",
    "unterminated XML construct",
  )
  let result = self.source[start:self.offset].to_owned()
  self.offset += token.length()
  result
}

///|
fn XmlCursor::name(self : XmlCursor) -> String raise ProcessError {
  let start = self.offset
  while self.offset < self.source.length() {
    let u = self.source.code_unit_at(self.offset).to_int()
    let valid = (u >= 65 && u <= 90) ||
      (u >= 97 && u <= 122) ||
      u == 95 ||
      u == 58 ||
      (self.offset > start && ((u >= 48 && u <= 57) || u == 45 || u == 46))
    if !valid {
      break
    }
    self.offset += 1
  }
  model_require(self.offset > start, "xml.name", "expected ASCII XML name")
  let name = self.source[start:self.offset].to_owned()
  let parts = name.split(":").collect()
  model_require(
    parts.length() <= 2 && parts.all(part => !part.is_empty()),
    "xml.name",
    "invalid QName",
  )
  name
}

///|
fn xml_entity(text : String) -> String raise ProcessError {
  let out = StringBuilder()
  let mut i = 0
  while i < text.length() {
    if text.code_unit_at(i).to_int() != 38 {
      let start = i
      while i < text.length() && text.code_unit_at(i).to_int() != 38 {
        i += 1
      }
      out.write_string(text[start:i].to_owned())
      continue
    }
    let start = i + 1
    i = start
    while i < text.length() && text.code_unit_at(i).to_int() != 59 {
      i += 1
    }
    model_require(i < text.length(), "xml.entity", "unterminated entity")
    let entity = text[start:i].to_owned()
    match entity {
      "amp" => out.write_string("&")
      "lt" => out.write_string("<")
      "gt" => out.write_string(">")
      "quot" => out.write_string("\"")
      "apos" => out.write_string("'")
      _ => {
        model_require(
          entity.has_prefix("#"),
          "xml.entity",
          "external/custom entity unsupported",
        )
        let hex = entity.has_prefix("#x")
        let mut value = 0
        let digits = entity[if hex { 2 } else { 1 }:].to_owned()
        model_require(
          !digits.is_empty() && digits.length() <= 8,
          "xml.entity",
          "invalid character reference",
        )
        for digit in digits {
          let unit = digit.to_int()
          let number = if unit >= 48 && unit <= 57 {
            unit - 48
          } else if hex && unit >= 65 && unit <= 70 {
            unit - 55
          } else if hex && unit >= 97 && unit <= 102 {
            unit - 87
          } else {
            -1
          }
          let base = if hex { 16 } else { 10 }
          model_require(
            number >= 0 && value <= (0x10FFFF - number) / base,
            "xml.entity",
            "invalid character reference",
          )
          value = value * base + number
        }
        model_require(xml_char(value), "xml.entity", "invalid XML character")
        out.write_char(value.unsafe_to_char())
      }
    }
    i += 1
  }
  out.to_string()
}

///|
fn xml_char(value : Int32) -> Bool {
  value == 9 ||
  value == 10 ||
  value == 13 ||
  (value >= 32 && value <= 0xD7FF) ||
  (value >= 0xE000 && value <= 0xFFFD) ||
  (value >= 0x10000 && value <= 0x10FFFF)
}

///|
fn xml_expanded(
  qname : String,
  spaces : Map[String, String],
  attribute : Bool,
) -> (String, String) raise ProcessError {
  match qname.split_once(":") {
    Some((prefix, name)) => {
      let ns = spaces
        .get(prefix.to_owned())
        .unwrap_or_else(() => {
          raise InvalidLog(path="xml.namespace", reason="undeclared prefix")
        })
      (ns, name.to_owned())
    }
    None => (if attribute { "" } else { spaces.get("").unwrap_or("") }, qname)
  }
}

///|
fn XmlCursor::element(
  self : XmlCursor,
  parent_spaces : Map[String, String],
  depth : Int32,
) -> ModelXml raise ProcessError {
  if depth > 48 {
    raise Capacity(resource="XML depth", limit=48)
  }
  if self.nodes >= 200000 {
    raise Capacity(resource="XML nodes", limit=200000)
  }
  self.nodes += 1
  self.take("<")
  let qname = self.name()
  let spaces = parent_spaces.copy()
  let raw : Map[String, String] = Map([])
  while true {
    let before = self.offset
    self.space()
    if self.at("/>") || self.at(">") {
      break
    }
    model_require(
      self.offset > before,
      "xml.attributes",
      "attributes require whitespace at \{self.offset}",
    )
    let name = self.name()
    model_require(!raw.contains(name), "xml.attributes", "duplicate attribute")
    if raw.length() >= 128 {
      raise Capacity(resource="XML attributes per node", limit=128)
    }
    self.space()
    self.take("=")
    self.space()
    model_require(
      self.at("\"") || self.at("'"),
      "xml.attribute",
      "quoted attribute required",
    )
    let quote = self.source[self.offset:self.offset + 1].to_owned()
    self.offset += 1
    let value = self.until(quote)
    model_require(!value.contains("<"), "xml.attribute", "literal < forbidden")
    let value = xml_entity(
      value.replace_all(old="\t", new=" ").replace_all(old="\n", new=" "),
    )
    raw[name] = value
    if name == "xmlns" {
      spaces[""] = value
    } else if name.has_prefix("xmlns:") {
      let prefix = name[6:].to_owned()
      model_require(
        prefix != "xmlns" &&
        value != "" &&
        (prefix != "xml" || value == "http://www.w3.org/XML/1998/namespace"),
        "xml.namespace",
        "reserved/empty namespace binding",
      )
      spaces[prefix] = value
    }
  }
  let (ns, name) = xml_expanded(qname, spaces, false)
  let attributes : Map[String, String] = Map([])
  for key, value in raw {
    if key == "xmlns" || key.has_prefix("xmlns:") {
      continue
    }
    let (space, local_name) = xml_expanded(key, spaces, true)
    let key = if space == "" { local_name } else { "{\{space}}\{local_name}" }
    model_require(
      !attributes.contains(key),
      "xml.attributes",
      "duplicate expanded attribute",
    )
    attributes[key] = value
  }
  let children = []
  let text = StringBuilder()
  if self.at("/>") {
    self.offset += 2
  } else {
    self.take(">")
    while !self.at("</") {
      model_require(
        self.offset < self.source.length(),
        "xml",
        "unclosed element",
      )
      if self.at("<!--") {
        self.offset += 4
        let comment = self.until("-->")
        model_require(
          !comment.contains("--") && !comment.has_suffix("-"),
          "xml.comment",
          "invalid comment",
        )
      } else if self.at("<![CDATA[") {
        self.offset += 9
        text.write_string(self.until("]]>"))
      } else if self.at("<") {
        model_require(
          !self.at("<!") && !self.at("<?"),
          "xml",
          "DTD and processing instructions unsupported",
        )
        children.push(self.element(spaces, depth + 1))
      } else {
        let start = self.offset
        while self.offset < self.source.length() && !self.at("<") {
          self.offset += 1
        }
        let chunk = self.source[start:self.offset].to_owned()
        model_require(
          !chunk.contains("]]>"),
          "xml",
          "CDATA close forbidden in text",
        )
        text.write_string(xml_entity(chunk))
      }
    }
    self.take("</")
    model_require(self.name() == qname, "xml", "mismatched closing tag")
    self.space()
    self.take(">")
  }
  { name, ns, attributes, children, text: text.to_string(), }
}

///|
// Non-validating, finite XML transport profile: ASCII element/attribute names,
// Unicode values, namespaces and predefined/numeric entities. No DTD/XXE/PI.
fn model_xml(text : String) -> ModelXml raise ProcessError {
  if text.length() > 16777216 {
    raise Capacity(resource="XML text units", limit=16777216)
  }
  for ch in text {
    model_require(xml_char(ch.to_int()), "xml", "invalid XML scalar")
  }
  let source = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let cursor = { source, offset: 0, nodes: 0, }
  if cursor.at("\uFEFF") {
    cursor.offset += 1
  }
  if cursor.at("<?xml ") {
    cursor.offset += 6
    let declaration = cursor.until("?>")
    let header = {
      source: "<declaration \{declaration}/>",
      offset: 0,
      nodes: 0,
    }.element(Map([]), 0)
    model_require(
      header.attributes.get("version") == Some("1.0"),
      "xml",
      "only XML 1.0 supported",
    )
    for key, value in header.attributes {
      model_require(
        ["version", "encoding", "standalone"].contains(key),
        "xml.declaration",
        "unknown declaration attribute",
      )
      if key == "encoding" {
        model_require(
          ["UTF-8", "UTF-16"].contains(value.to_upper()),
          "xml.declaration",
          "unsupported character encoding label",
        )
      }
      if key == "standalone" {
        model_require(
          value == "yes" || value == "no",
          "xml.declaration",
          "invalid standalone value",
        )
      }
    }
  }
  cursor.misc()
  let root = cursor.element(
    Map([("xml", "http://www.w3.org/XML/1998/namespace")]),
    0,
  )
  cursor.misc()
  model_require(
    cursor.offset == source.length(),
    "xml",
    "trailing content unsupported",
  )
  root
}

///|
fn ModelXml::attribute(
  self : ModelXml,
  key : String,
) -> String raise ProcessError {
  self.attributes
  .get(key)
  .unwrap_or_else(() => {
    raise InvalidLog(path="xml.attribute", reason="missing \{key}")
  })
}

///|
fn xml_escape(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&apos;")
}

///|
fn ModelXml::only_attributes(
  self : ModelXml,
  allowed : Array[String],
) -> Unit raise ProcessError {
  for key, _ in self.attributes {
    model_require(
      allowed.contains(key),
      "xml.attributes",
      "unsupported semantic attribute: \{key}",
    )
  }
}
