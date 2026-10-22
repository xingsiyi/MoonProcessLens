///|
fn read_text(path : String) -> String raise {
  let text = @fs.read_file_to_string(path)
  if text.length() > 16777216 {
    raise @cep.Resource(resource="CLI input UTF-16 units", limit=16777216)
  }
  text
}

///|
fn print_batch(program : @cep.Program, batch : @cep.Batch) -> Unit raise {
  println(@cep.batch_to_json(batch).stringify())
  for record in program.project(batch) {
    println(@cep.alert_record_to_json(record).stringify())
  }
}

///|
fn run(args : Array[String]) -> Unit raise {
  if args.length() < 3 {
    println(
      "usage: mooncep validate CONFIG | run CONFIG COMMANDS.ndjson | restore SESSION.json COMMANDS.ndjson | inspect SESSION.json",
    )
    @sys.exit(2)
    return
  }
  match args[1] {
    "validate" => {
      if args.length() != 3 {
        @sys.exit(2)
        return
      }
      let program = @cep.parse_program(read_text(args[2]))
      println(program.describe().stringify())
    }
    "run" => {
      if args.length() != 4 {
        @sys.exit(2)
        return
      }
      let program = @cep.parse_program(read_text(args[2]))
      let monitor = program.monitor()
      let text = read_text(args[3])
      // File input is chunked through the same transactional interface used by
      // network adapters. The CLI itself loads one bounded file into memory.
      for chunk in @cep.command_chunks(text) {
        for batch in monitor.ingest(chunk.to_owned()) {
          print_batch(program, batch)
        }
      }
      for batch in monitor.finish_input() {
        print_batch(program, batch)
      }
      println(@cep.monitor_stats_to_json(monitor.stats()).stringify())
    }
    "inspect" => {
      if args.length() != 3 {
        @sys.exit(2)
        return
      }
      let session = @cep.parse_session(read_text(args[2]))
      println(
        @cep.inspection_to_json(session.checkpoint().restore().inspect()).stringify(),
      )
    }
    "restore" => {
      if args.length() != 4 {
        @sys.exit(2)
        return
      }
      let session = @cep.parse_session(read_text(args[2]))
      let reader = @cep.CommandReader::new()
      let commands = reader.feed(read_text(args[3]))
      commands.append(reader.finish())
      for update in session.apply_many(commands) {
        match update {
          @cep.Accepted(_) => ()
          @cep.Progress(batch) => println(@cep.batch_to_json(batch).stringify())
        }
      }
      println(@cep.batch_to_json(session.finish()).stringify())
    }
    _ => {
      println("unknown command")
      @sys.exit(2)
    }
  }
}

///|
fn main {
  run(@env.args()) catch {
    error => {
      println("ERROR: \{error.to_string()}")
      @sys.exit(1)
    }
  }
}
