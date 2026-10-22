///|
pub(all) struct MonitorStats {
  accepted_events : Int64
  advances : Int64
  matches : Int64
  timeouts : Int64
  work : Int64
  buffered_events : Int
  active_states : Int
  pending_text_units : Int
}

///|
/// Owns the text-framing and detection transaction boundary for an application.
/// Failed ingestion commits neither partial text nor journal or detector state.
pub struct Monitor {
  mut reader : CommandReader
  mut session : Session
  mut accepted_events : Int64
  mut advances : Int64
  mut matches : Int64
  mut timeouts : Int64
  mut work : Int64
}

///|
pub fn Monitor::new(
  patterns : Array[Pattern],
  limits~ : Limits = Limits::default(),
  max_commands~ : Int = 10000,
  max_line~ : Int = 1048576,
  commands_per_chunk~ : Int = 4096,
) -> Monitor raise CepError {
  {
    reader: CommandReader::new(max_line~, max_commands=commands_per_chunk),
    session: Session::new(patterns, limits~, max_commands~),
    accepted_events: 0L,
    advances: 0L,
    matches: 0L,
    timeouts: 0L,
    work: 0L,
  }
}

///|
pub fn Monitor::fork(self : Monitor) -> Monitor {
  { ..self, reader: self.reader.fork(), session: self.session.fork() }
}

///|
fn Monitor::commit(self : Monitor, staged : Monitor) -> Unit {
  self.reader = staged.reader
  self.session = staged.session
  self.accepted_events = staged.accepted_events
  self.advances = staged.advances
  self.matches = staged.matches
  self.timeouts = staged.timeouts
  self.work = staged.work
}

///|
fn Monitor::execute(self : Monitor, commands : Array[StreamInput]) -> Array[Batch] raise CepError {
  let batches = []
  let mut emitted = 0
  for command in commands {
    match self.session.apply(command) {
      Accepted(_) => self.accepted_events += 1L
      Progress(batch) => {
        let added = batch.matches.length() + batch.timeouts.length()
        if added > self.session.engine.limits.outputs_per_call - emitted {
          raise Resource(resource="monitor outputs per call", limit=self.session.engine.limits.outputs_per_call)
        }
        emitted += added
        self.advances += 1L
        self.matches += batch.matches.length().to_int64()
        self.timeouts += batch.timeouts.length().to_int64()
        self.work += batch.work.to_int64()
        batches.push(batch)
      }
    }
  }
  batches
}

///|
pub fn Monitor::ingest(self : Monitor, chunk : String) -> Array[Batch] raise CepError {
  let staged = self.fork()
  let commands = staged.reader.feed(chunk)
  let batches = staged.execute(commands)
  self.commit(staged)
  batches
}

///|
/// Finish the final non-newline-terminated command. By default also close all
/// event-time deadlines. A repeated successful finish returns no new batches.
pub fn Monitor::finish_input(self : Monitor, close_time~ : Bool = true) -> Array[Batch] raise CepError {
  if self.reader.closed { return [] }
  let staged = self.fork()
  let commands = staged.reader.finish()
  if close_time { commands.push(Advance(9007230790740991L)) }
  let batches = staged.execute(commands)
  self.commit(staged)
  batches
}

///|
pub fn Monitor::stats(self : Monitor) -> MonitorStats {
  {
    accepted_events: self.accepted_events,
    advances: self.advances,
    matches: self.matches,
    timeouts: self.timeouts,
    work: self.work,
    buffered_events: self.session.buffered(),
    active_states: self.session.active_states(),
    pending_text_units: self.reader.pending_units(),
  }
}

///|
pub fn Monitor::inspection(self : Monitor) -> Inspection {
  self.session.engine.inspect()
}

///|
pub fn Monitor::session(self : Monitor) -> Session {
  self.session.fork()
}

///|
pub fn monitor_stats_to_json(stats : MonitorStats) -> Json {
  {
    "accepted_events": Json::string(stats.accepted_events.to_string()),
    "advances": Json::string(stats.advances.to_string()),
    "matches": Json::string(stats.matches.to_string()),
    "timeouts": Json::string(stats.timeouts.to_string()),
    "work": Json::string(stats.work.to_string()),
    "buffered_events": Json::number(stats.buffered_events.to_double()),
    "active_states": Json::number(stats.active_states.to_double()),
    "pending_text_units": Json::number(stats.pending_text_units.to_double()),
  }
}
