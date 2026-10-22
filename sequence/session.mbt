///|
pub(all) enum Update {
  Accepted(Int64)
  Progress(Batch)
}

///|
/// A bounded input journal coupled atomically to an in-memory recognizer.
/// Replaying a journal reconstructs detection state, not external sink delivery.
pub struct Session {
  mut engine : Engine
  mut commands : Array[StreamInput]
  max_commands : Int32
}

///|
pub fn Session::new(
  patterns : Array[Pattern],
  limits~ : Limits = Limits::default(),
  max_commands~ : Int32 = 10000,
) -> Session raise CepError {
  if max_commands < 1 || max_commands > 100000 {
    raise Invalid(path="session.max_commands", reason="expected 1..100000")
  }
  { engine: Engine::new(patterns, limits~), commands: [], max_commands, }
}

///|
pub fn Session::apply(
  self : Session,
  command : StreamInput,
) -> Update raise CepError {
  if self.commands.length() >= self.max_commands {
    raise Resource(resource="journal commands", limit=self.max_commands)
  }
  let update = match command {
    Observe(event) => Accepted(self.engine.push(event))
    Advance(time) => Progress(self.engine.advance_watermark(time))
  }
  self.commands.push(command)
  update
}

///|
pub fn Session::fork(self : Session) -> Session {
  {
    engine: self.engine.fork(),
    commands: self.commands.copy(),
    max_commands: self.max_commands,
  }
}

///|
pub fn Session::apply_many(
  self : Session,
  commands : Array[StreamInput],
) -> Array[Update] raise CepError {
  if commands.length() > self.max_commands - self.commands.length() {
    raise Resource(resource="journal commands", limit=self.max_commands)
  }
  let staged = self.fork()
  let results = []
  let mut outputs = 0
  for command in commands {
    let update = staged.apply(command)
    if update is Progress(batch) {
      let count = batch.matches.length() + batch.timeouts.length()
      if count > self.engine.limits.outputs_per_call - outputs {
        raise Resource(
          resource="session batch outputs",
          limit=self.engine.limits.outputs_per_call,
        )
      }
      outputs += count
    }
    results.push(update)
  }
  self.engine = staged.engine
  self.commands = staged.commands
  results
}

///|
pub fn Session::finish(self : Session) -> Batch raise CepError {
  match self.apply(Advance(9007230790740991L)) {
    Progress(batch) => batch
    Accepted(_) => abort("unreachable: Advance returns Progress")
  }
}

///|
pub fn Session::commands(self : Session) -> Array[StreamInput] {
  self.commands.copy()
}

///|
pub fn Session::checkpoint(self : Session) -> Checkpoint {
  self.engine.checkpoint()
}

///|
pub fn Session::watermark(self : Session) -> Int64 {
  self.engine.watermark
}

///|
pub fn Session::buffered(self : Session) -> Int32 {
  self.engine.buffer.length()
}

///|
pub fn Session::active_states(self : Session) -> Int32 {
  self.engine.active.length()
}

///|
pub fn Session::with_limits(
  self : Session,
  limits : Limits,
) -> Session raise CepError {
  {
    engine: self.engine.with_limits(limits),
    commands: self.commands.copy(),
    max_commands: self.max_commands,
  }
}
