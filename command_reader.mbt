///|
/// Incremental UTF-16 text framing for newline-delimited stream commands.
/// CRLF and blank lines are accepted. Parsing and reader state commit together.
pub struct CommandReader {
  mut partial : String
  mut line : Int32
  mut closed : Bool
  max_line : Int32
  max_commands : Int32
}

///|
pub fn CommandReader::new(
  max_line~ : Int32 = 1048576,
  max_commands~ : Int32 = 4096,
) -> CommandReader raise CepError {
  if max_line < 1 || max_line > 1048576 {
    raise Invalid(
      path="reader.max_line",
      reason="expected 1..1048576 UTF-16 units",
    )
  }
  if max_commands < 1 || max_commands > 100000 {
    raise Invalid(path="reader.max_commands", reason="expected 1..100000")
  }
  { partial: "", line: 1, closed: false, max_line, max_commands, }
}

///|
fn read_command_line(
  text : String,
  line : Int32,
) -> StreamInput? raise CepError {
  let stripped = text.trim()
  if stripped.length() == 0 {
    return None
  }
  Some(parse_command(stripped.to_owned())) catch {
    Invalid(path~, reason~) =>
      raise Invalid(path="line[\{line}].\{path}", reason~)
    error => raise error
  }
}

///|
pub fn CommandReader::feed(
  self : CommandReader,
  chunk : String,
) -> Array[StreamInput] raise CepError {
  if self.closed {
    raise Invalid(path="reader", reason="reader is already finished")
  }
  let mut builder = StringBuilder()
  builder.write_string(self.partial)
  let mut units = self.partial.length()
  let mut line = self.line
  let commands = []
  let mut segment = 0
  for index in 0..<chunk.length() {
    if chunk.code_unit_at(index).to_int() == 10 {
      builder.write_view(chunk[segment:index])
      if read_command_line(builder.to_string(), line) is Some(command) {
        if commands.length() >= self.max_commands {
          raise Resource(resource="commands per chunk", limit=self.max_commands)
        }
        commands.push(command)
      }
      builder = StringBuilder()
      units = 0
      if line == 2147483647 {
        raise Invalid(path="reader.line", reason="line counter exhausted")
      }
      line += 1
      segment = index + 1
    } else {
      if units >= self.max_line {
        raise Resource(resource="line UTF-16 units", limit=self.max_line)
      }
      units += 1
    }
  }
  builder.write_view(chunk[segment:])
  self.partial = builder.to_string()
  self.line = line
  commands
}

///|
pub fn CommandReader::finish(
  self : CommandReader,
) -> Array[StreamInput] raise CepError {
  if self.closed {
    return []
  }
  let result = match read_command_line(self.partial, self.line) {
    Some(command) => [command]
    None => []
  }
  self.partial = ""
  self.closed = true
  result
}

///|
pub fn CommandReader::pending_units(self : CommandReader) -> Int32 {
  self.partial.length()
}

///|
pub fn CommandReader::line(self : CommandReader) -> Int32 {
  self.line
}

///|
pub fn CommandReader::is_finished(self : CommandReader) -> Bool {
  self.closed
}

///|
pub fn CommandReader::fork(self : CommandReader) -> CommandReader {
  { ..self, }
}

///|
/// Chunk a complete Unicode string without discarding a scalar at a UTF-16
/// boundary. A two-unit scalar can exceed a requested size of one by one unit.
pub fn command_chunks(text : String, max_units~ : Int = 65536) -> Iter[StringView] raise CepError {
  if max_units < 1 || max_units > 1048576 {
    raise Invalid(path="chunks.max_units", reason="expected 1..1048576")
  }
  let mut position = 0
  Iter::new(fn() -> StringView? {
    if position == text.length() { return None }
    let size = max_units.min(text.length() - position)
    let mut view = text.clamped_view(start=position, end=position + size)
    if view.length() == 0 {
      view = text.exact_view(start=position, end=position + 2)
    }
    position += view.length()
    Some(view)
  })
}
