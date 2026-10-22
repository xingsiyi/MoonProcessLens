///|
pub fn program_to_json(program : Program) -> Json {
  {
    "schema_version": 1,
    "patterns": Json::array(program.patterns.map(pattern_to_json)),
    "limits": limits_to_json(program.limits),
    "projections": Json::array(program.projections.map(projection_to_json)),
  }
}

///|
pub fn program_from_json(value : Json) -> Program raise CepError {
  let object = codec_object(value, "program")
  codec_keys(
    object,
    ["schema_version", "patterns", "limits", "projections"],
    "program",
  )
  if codec_int32(
      codec_required(object, "schema_version", "program"),
      "program.schema_version",
    ) !=
    1 {
    raise Invalid(
      path="program.schema_version",
      reason="only version 1 is supported",
    )
  }
  let entries = codec_array(
    codec_required(object, "patterns", "program"),
    "program.patterns",
  )
  if entries.length() > 64 {
    raise Resource(resource="patterns", limit=64)
  }
  let patterns = entries.map(pattern_from_json)
  let limits = limits_from_json(codec_required(object, "limits", "program"))
  let projection_json = codec_array(
    codec_required(object, "projections", "program"),
    "program.projections",
  )
  if projection_json.length() > 64 {
    raise Resource(resource="projections", limit=64)
  }
  let plans : Array[ProjectionPlan] = []
  for item in projection_json {
    let target = codec_text_property(
      codec_object(item, "projection"),
      "pattern",
      "projection",
    )
    let mut pattern : Pattern? = None
    for candidate in patterns {
      if candidate.id == target {
        pattern = Some(candidate)
      }
    }
    match pattern {
      Some(pattern) => plans.push(projection_from_json(pattern, item))
      None =>
        raise Invalid(
          path="projection.pattern",
          reason="unknown pattern \{target}",
        )
    }
  }
  Program::new(patterns, limits~, projections=plans)
}

///|
pub fn parse_program(text : String) -> Program raise CepError {
  program_from_json(codec_parse(text, max_depth=128))
}

///|
pub fn format_program(program : Program) -> String raise CepError {
  codec_bounded_format(program_to_json(program))
}

///|
pub fn Program::describe(self : Program) -> Json {
  {
    "limits": limits_to_json(self.limits),
    "patterns": Json::array(
      self.patterns.map(pattern => {
        let analysis = pattern.analysis()
        {
          "id": Json::string(pattern.id),
          "within": Json::string(pattern.within.to_string()),
          "stages": Json::number(pattern.stages.length().to_double()),
          "minimum_captures": Json::number(
            analysis.minimum_captures.to_double(),
          ),
          "maximum_captures": Json::number(
            analysis.maximum_captures.to_double(),
          ),
          "nullable_stages": Json::number(analysis.nullable_stages.to_double()),
          "has_absence": Json::boolean(analysis.has_absence),
          "branching": Json::string(
            match analysis.branching_risk {
              FixedSequence => "fixed_sequence"
              BoundedRepetition => "bounded_repetition"
              CombinatorialSelection => "combinatorial_selection"
            },
          ),
        }
      }),
    ),
    "projection_count": Json::number(self.projections.length().to_double()),
  }
}
