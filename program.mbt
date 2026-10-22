///|
/// A validated deployable set of patterns, budgets and optional alert projections.
pub struct Program {
  patterns : Array[Pattern]
  limits : Limits
  projections : Array[ProjectionPlan]
}

///|
pub fn Program::new(
  patterns : Array[Pattern],
  limits~ : Limits = Limits::default(),
  projections~ : Array[ProjectionPlan] = [],
) -> Program raise CepError {
  let validated = Engine::new(patterns, limits~)
  if projections.length() > patterns.length() {
    raise Invalid(
      path="program.projections",
      reason="at most one projection per pattern",
    )
  }
  let seen : Map[String, Bool] = Map([])
  let plans = []
  for plan in projections {
    if seen.contains(plan.pattern) {
      raise Invalid(
        path="program.projections",
        reason="duplicate projection for \{plan.pattern}",
      )
    }
    seen.set(plan.pattern, true)
    let mut target : Pattern? = None
    for pattern in patterns {
      if pattern.id == plan.pattern {
        target = Some(pattern)
      }
    }
    match target {
      Some(pattern) => plans.push(ProjectionPlan::new(pattern, plan.columns))
      None =>
        raise Invalid(
          path="program.projections",
          reason="projection references unknown pattern",
        )
    }
  }
  { patterns: validated.patterns, limits, projections: plans, }
}

///|
pub fn Program::patterns(self : Program) -> Array[Pattern] {
  self.patterns.map(clone_pattern)
}

///|
pub fn Program::limits(self : Program) -> Limits {
  self.limits
}

///|
pub fn Program::projections(self : Program) -> Array[ProjectionPlan] {
  self.projections.map(plan => { ..plan, columns: plan.columns.copy(), })
}

///|
pub fn Program::engine(self : Program) -> Engine raise CepError {
  Engine::new(self.patterns, limits=self.limits)
}

///|
pub fn Program::monitor(
  self : Program,
  max_commands~ : Int32 = 10000,
) -> Monitor raise CepError {
  Monitor::new(self.patterns, limits=self.limits, max_commands~)
}

///|
pub(all) struct AlertRecord {
  pattern : String
  key : String
  identity : String
  fields : Array[Field]
}

///|
/// Project only matches with a configured projection. Failure returns no partial
/// records and never changes the already committed recognition batch.
pub fn Program::project(
  self : Program,
  batch : Batch,
) -> Array[AlertRecord] raise CepError {
  let records = []
  for value in batch.matches {
    for plan in self.projections {
      if plan.pattern == value.pattern {
        records.push({
          pattern: value.pattern,
          key: value.key,
          identity: value.identity(),
          fields: plan.apply(value),
        })
      }
    }
  }
  records
}

///|
pub fn alert_record_to_json(record : AlertRecord) -> Json raise CepError {
  {
    "pattern": Json::string(record.pattern),
    "key": Json::string(record.key),
    "identity": Json::string(record.identity),
    "fields": projected_record_to_json(record.fields),
  }
}
