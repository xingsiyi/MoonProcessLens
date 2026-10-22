///|
pub(all) struct Limits {
  buffered_events : Int32
  active_states : Int32
  partitions : Int32
  outputs_per_call : Int32
  work_per_call : Int32
} derive(Eq, @debug.Debug)

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub fn Limits::default() -> Limits {
  {
    buffered_events: 4096,
    active_states: 8192,
    partitions: 1024,
    outputs_per_call: 4096,
    work_per_call: 1000000,
  }
}

///|
pub fn Limits::validate(self : Limits) -> Unit raise CepError {
  for
    (name, value, maximum) in [
      ("buffered events", self.buffered_events, 100000),
      ("active states", self.active_states, 100000),
      ("partitions", self.partitions, 100000),
      ("outputs per call", self.outputs_per_call, 100000),
      ("work per call", self.work_per_call, 100000000),
    ] {
    if value < 1 || value > maximum {
      raise Invalid(path="limits.\{name}", reason="expected 1..\{maximum}")
    }
  }
}

///|
priv struct Work {
  mut used : Int32
  limit : Int32
}

///|
fn Work::charge(self : Work, amount~ : Int = 1) -> Unit raise CepError {
  if amount < 0 || amount > self.limit - self.used {
    raise Resource(resource="work per call", limit=self.limit)
  }
  self.used += amount
}
