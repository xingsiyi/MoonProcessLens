///|
/// A command for deterministic, explicitly watermarked in-memory replay.
pub(all) enum StreamInput {
  Observe(Event)
  Advance(Int64)
} derive(Eq, @debug.Debug)

///|
pub extend StreamInput with Eq::{equal, not_equal}

///|
pub extend StreamInput with @debug.Debug::{to_repr}

///|
fn clone_integration_event(event : Event) -> Event {
  { ..event, fields: event.fields.copy(), }
}

///|
fn clone_integration_captures(captures : Array[Capture]) -> Array[Capture] {
  captures.map(capture => {
    name: capture.name,
    events: capture.events.map(clone_integration_event),
  })
}

///|
/// Creates an independent engine at the same committed point, including
/// buffered observations, capture evidence and mutable condition child arrays.
pub fn Engine::fork(self : Engine) -> Engine {
  {
    patterns: self.patterns.map(clone_pattern),
    limits: self.limits,
    buffer: self.buffer.map(item => {
      event: clone_integration_event(item.event),
      ordinal: item.ordinal,
    }),
    active: self.active.map(branch => {
      ..branch,
      captures: clone_integration_captures(branch.captures),
      positions: branch.positions.copy(),
    }),
    watermark: self.watermark,
    ordinal: self.ordinal,
  }
}

///|
/// Returns a detached engine with replacement budgets. Existing buffered
/// events, branches and active keys must fit; output/work limits govern future
/// calls. This supports retrying a failed advance with larger budgets.
pub fn Engine::with_limits(
  self : Engine,
  limits : Limits,
) -> Engine raise CepError {
  limits.validate()
  if self.buffer.length() > limits.buffered_events {
    raise Resource(resource="buffered events", limit=limits.buffered_events)
  }
  if self.active.length() > limits.active_states {
    raise Resource(resource="active states", limit=limits.active_states)
  }
  let keys : Map[String, Bool] = Map([])
  for branch in self.active {
    keys.set(branch.key, true)
  }
  if keys.length() > limits.partitions {
    raise Resource(resource="partitions", limit=limits.partitions)
  }
  let detached = self.fork()
  { ..detached, limits, }
}

///|
/// Accepts the entire batch or leaves the engine unchanged. In particular,
/// a late event or an exhausted buffer cannot partially consume ordinals.
pub fn Engine::push_many(
  self : Engine,
  events : Array[Event],
) -> Array[Int64] raise CepError {
  let staged = self.fork()
  let ordinals : Array[Int64] = []
  for event in events {
    ordinals.push(staged.push(event))
  }
  self.buffer = staged.buffer
  self.active = staged.active
  self.watermark = staged.watermark
  self.ordinal = staged.ordinal
  ordinals
}

///|
/// An owned, in-process checkpoint. This is not a serialized durable format
/// and does not coordinate external sources, result delivery or transactions.
pub struct Checkpoint {
  state : Engine
}

///|
/// Takes a detached checkpoint; later engine mutations do not change it.
pub fn Engine::checkpoint(self : Engine) -> Checkpoint {
  { state: self.fork(), }
}

///|
/// Each restore returns a new engine, independent of all earlier restores.
pub fn Checkpoint::restore(self : Checkpoint) -> Engine {
  self.state.fork()
}

///|
/// Restores independently with validated replacement budgets.
pub fn Checkpoint::restore_with_limits(
  self : Checkpoint,
  limits : Limits,
) -> Engine raise CepError {
  self.state.with_limits(limits)
}

///|
pub fn Checkpoint::watermark(self : Checkpoint) -> Int64 {
  self.state.watermark
}

///|
pub fn Checkpoint::buffered(self : Checkpoint) -> Int32 {
  self.state.buffer.length()
}

///|
pub fn Checkpoint::active_states(self : Checkpoint) -> Int32 {
  self.state.active.length()
}

///|
/// Replays exactly the supplied commands and returns one batch per Advance.
/// There is no implicit final watermark. Each Advance has its own engine work
/// budget; replay separately bounds command count and aggregate result count.
/// On failure no intermediate batches escape, and input objects are unchanged.
pub fn replay(
  patterns : Array[Pattern],
  commands : Array[StreamInput],
  limits~ : Limits = Limits::default(),
  max_commands~ : Int32 = 10000,
  max_outputs~ : Int32 = 100000,
) -> Array[Batch] raise CepError {
  if max_commands < 1 || max_commands > 100000 {
    raise Invalid(path="replay.max_commands", reason="expected 1..100000")
  }
  if max_outputs < 1 || max_outputs > 1000000 {
    raise Invalid(path="replay.max_outputs", reason="expected 1..1000000")
  }
  if commands.length() > max_commands {
    raise Resource(resource="replay commands", limit=max_commands)
  }
  let engine = Engine::new(patterns, limits~)
  let batches : Array[Batch] = []
  let mut outputs = 0
  for command in commands {
    match command {
      Observe(event) => ignore(engine.push(event))
      Advance(watermark) => {
        let batch = engine.advance_watermark(watermark)
        let emitted = batch.matches.length() + batch.timeouts.length()
        if emitted > max_outputs - outputs {
          raise Resource(resource="replay outputs", limit=max_outputs)
        }
        outputs += emitted
        batches.push(batch)
      }
    }
  }
  batches
}
