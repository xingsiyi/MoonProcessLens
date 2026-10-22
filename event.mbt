///|
pub struct Event {
  id : String
  key : String
  time : Int64
  kind : String
  fields : Array[Field]
} derive(Eq, @debug.Debug)

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
pub fn Event::new(
  id : String,
  key : String,
  time : Int64,
  kind : String,
  fields~ : Array[Field] = [],
) -> Event raise CepError {
  require_label(id, "event.id")
  require_label(key, "event.key")
  require_label(kind, "event.kind")
  if time < 0L || time > 9007199254740991L {
    raise Invalid(path="event.time", reason="expected 0..9007199254740991")
  }
  if fields.length() > 128 {
    raise Resource(resource="event fields", limit=128)
  }
  let names : Map[String, Bool] = Map([])
  for field in fields {
    require_label(field.name, "event.field.name")
    field.value.validate()
    if names.contains(field.name) {
      raise Invalid(path="event.fields", reason="duplicate field \{field.name}")
    }
    names.set(field.name, true)
  }
  { id, key, time, kind, fields: fields.copy(), }
}

///|
pub fn Event::id(self : Event) -> String {
  self.id
}

///|
pub fn Event::key(self : Event) -> String {
  self.key
}

///|
pub fn Event::time(self : Event) -> Int64 {
  self.time
}

///|
pub fn Event::kind(self : Event) -> String {
  self.kind
}

///|
pub fn Event::fields(self : Event) -> Array[Field] {
  self.fields.copy()
}

///|
pub fn Event::field(self : Event, name : String) -> Value? {
  for field in self.fields {
    if field.name == name {
      return Some(field.value)
    }
  }
  None
}
