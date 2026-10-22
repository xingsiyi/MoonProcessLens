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
  for ch in chunk {
    if ch == '\n' {
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
    } else {
      let added = if ch.to_int() > 65535 { 2 } else { 1 }
      if added > self.max_line - units {
        raise Resource(resource="line UTF-16 units", limit=self.max_line)
      }
      builder.write_char(ch)
      units += added
    }
  }
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
