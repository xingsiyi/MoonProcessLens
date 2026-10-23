///|
fn read_document(path : String) -> String raise {
  let text = @fs.read_file_to_string(path)
  if text.length() > 16777216 {
    raise @lens.Capacity(resource="CLI text", limit=16777216)
  }
  text
}

///|
fn read_log(path : String) -> @lens.EventLog raise {
  let text = read_document(path)
  if path.to_lower().has_suffix(".xes") {
    @lens.parse_xes(text)
  } else {
    @lens.parse_log(text)
  }
}

///|
fn read_model(path : String) -> @lens.PetriNet raise {
  let text = read_document(path)
  if path.to_lower().has_suffix(".bpmn") {
    @lens.parse_bpmn(text).to_petri_net()
  } else if path.to_lower().has_suffix(".pnml") {
    @lens.parse_pnml(text)
  } else {
    @lens.parse_net(text)
  }
}

///|
fn run(args : Array[String]) -> Unit raise {
  if args.length() < 3 {
    println(
      "usage: processlens analyze LOG | align LOG REFERENCES.json | discover LOG alpha|prefix | discover-pnml LOG alpha|prefix | check LOG MODEL | model MODEL | to-xes LOG | from-xes LOG.xes completed|pairs | audit LOG POLICIES.json | compare BEFORE AFTER | resources LOG",
    )
    @sys.exit(2)
    return
  }
  match args[1] {
    "analyze" if args.length() == 3 => {
      let log = read_log(args[2])
      println(@lens.process_map_to_json(log.discover()).stringify())
      println(@lens.performance_to_json(log.performance()).stringify())
    }
    "align" if args.length() == 4 => {
      let log = read_log(args[2])
      let spec = @lens.parse_alignment_spec(read_document(args[3]))
      // Validate all case results before emitting any document.
      let results = log.align(spec.paths(), costs=spec.costs())
      for result in results {
        println(@lens.alignment_to_json(result).stringify())
      }
    }
    "discover" | "discover-pnml" if args.length() == 4 => {
      let log = read_log(args[2])
      let net = match args[3] {
        "alpha" => log.discover_alpha()
        "prefix" => log.discover_prefix_net()
        _ =>
          raise @lens.InvalidLog(
            path="discovery.algorithm",
            reason="expected alpha or prefix",
          )
      }
      println(
        if args[1] == "discover" {
          net.to_json().stringify()
        } else {
          net.to_pnml()
        },
      )
    }
    "check" if args.length() == 4 => {
      let log = read_log(args[2])
      if log.case_count() == 0 {
        raise @lens.InvalidLog(
          path="check.log",
          reason="cannot pass a check without cases",
        )
      }
      let net = read_model(args[3])
      let results = log.align_net(net)
      let output : Json = {
        "model": @lens.model_analysis_to_json(net.analyze()),
        "alignments": Json::array(results.map(@lens.model_alignment_to_json)),
      }
      println(output.stringify())
      if !results.all(result => result.conforming) {
        @sys.exit(3)
      }
    }
    "model" if args.length() == 3 =>
      println(
        @lens.model_analysis_to_json(read_model(args[2]).analyze()).stringify(),
      )
    "to-xes" if args.length() == 3 => println(read_log(args[2]).to_xes())
    "from-xes" if args.length() == 4 => {
      let mode = match args[3] {
        "completed" => @lens.Completed
        "pairs" => @lens.LifecyclePairs
        _ =>
          raise @lens.InvalidLog(
            path="xes.mode",
            reason="expected completed or pairs",
          )
      }
      println(
        @lens.log_to_json(@lens.parse_xes(read_document(args[2]), mode~)).stringify(),
      )
    }
    "audit" if args.length() == 4 => {
      let log = read_log(args[2])
      let results = log.check_policies(
        @lens.parse_policies(read_document(args[3])),
      )
      println(@lens.policy_results_to_json(results).stringify())
      if results.any(result => {
          result.status == Violated || result.status == Inconclusive
        }) {
        @sys.exit(3)
      }
    }
    "compare" if args.length() == 4 =>
      println(
        @lens.cohort_comparison_to_json(
          read_log(args[2]).compare_cohort(read_log(args[3])),
        ).stringify(),
      )
    "resources" if args.length() == 3 =>
      println(
        @lens.resource_handoffs_to_json(read_log(args[2]).resource_handoffs()).stringify(),
      )
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
      match error {
        @lens.InvalidLog(path~, reason~) =>
          println("ERROR at \{path}: \{reason}")
        @lens.Capacity(resource~, limit~) =>
          println("ERROR: capacity \{resource} exceeded (\{limit})")
        _ => println("ERROR: \{error.to_string()}")
      }
      @sys.exit(1)
    }
  }
}
