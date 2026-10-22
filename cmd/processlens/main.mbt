///|
fn read_document(path : String) -> String raise {
  let text = @fs.read_file_to_string(path)
  if text.length() > 16777216 {
    raise @lens.Capacity(resource="CLI text", limit=16777216)
  }
  text
}

///|
fn run(args : Array[String]) -> Unit raise {
  if args.length() < 3 {
    println(
      "usage: processlens analyze LOG.json | align LOG.json REFERENCES.json",
    )
    @sys.exit(2)
    return
  }
  match args[1] {
    "analyze" if args.length() == 3 => {
      let log = @lens.parse_log(read_document(args[2]))
      println(@lens.process_map_to_json(log.discover()).stringify())
      println(@lens.performance_to_json(log.performance()).stringify())
    }
    "align" if args.length() == 4 => {
      let log = @lens.parse_log(read_document(args[2]))
      let spec = @lens.parse_alignment_spec(read_document(args[3]))
      // Validate all case results before emitting any document.
      let results = log.align(spec.paths(), costs=spec.costs())
      for result in results {
        println(@lens.alignment_to_json(result).stringify())
      }
    }
    _ => {
      println("unknown command or wrong argument count")
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
