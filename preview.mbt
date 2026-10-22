///|
pub struct Preview {
  batch : Batch
  inspection : Inspection
  frontier : Frontier
}

///|
pub fn Preview::batch(self : Preview) -> Batch {
  {
    ..self.batch,
    matches: self.batch.matches(),
    timeouts: self.batch.timeouts(),
  }
}

///|
pub fn Preview::inspection(self : Preview) -> Inspection {
  {
    ..self.inspection,
    partitions: self.inspection.partitions.copy(),
    patterns: self.inspection.patterns.copy(),
  }
}

///|
pub fn Preview::frontier(self : Preview) -> Frontier {
  { items: self.frontier.items(), total: self.frontier.total, }
}

///|
/// Preview a batch of observations and one watermark against a detached engine.
/// Existing buffered observations through that watermark are also processed.
/// Neither success nor failure changes the original engine or its ordinals.
pub fn Engine::preview(
  self : Engine,
  events : Array[Event],
  watermark : Int64,
  frontier_limit~ : Int32 = 128,
) -> Preview raise CepError {
  let staged = self.fork()
  ignore(staged.push_many(events))
  let batch = staged.advance_watermark(watermark)
  {
    batch,
    inspection: staged.inspect(),
    frontier: staged.frontier(limit=frontier_limit),
  }
}

///|
pub(all) struct StageDiagnostic {
  stage : String
  positive : Evaluation
  forbidden : Evaluation?
  minimum : Int32
  maximum : Int32
}

///|
/// Explain each stage's predicates against supplied capture context. This is a
/// predicate diagnostic, not a claim that the event can complete the sequence.
pub fn Pattern::diagnose(
  self : Pattern,
  event : Event,
  captures~ : Array[Capture] = [],
) -> Array[StageDiagnostic] raise CepError {
  self.stages.map(stage => {
    stage: stage.name,
    positive: stage.condition.explain(event, captures~),
    forbidden: stage.forbidden.map(condition => {
      condition.explain(event, captures~)
    }),
    minimum: stage.min,
    maximum: stage.max,
  })
}

///|
pub fn stage_diagnostics_to_json(diagnostics : Array[StageDiagnostic]) -> Json {
  Json::array(
    diagnostics.map(item => {
      "stage": Json::string(item.stage),
      "positive": evaluation_to_json(item.positive),
      "forbidden": match item.forbidden {
        Some(evaluation) => evaluation_to_json(evaluation)
        None => Json::null()
      },
      "minimum": Json::number(item.minimum.to_double()),
      "maximum": Json::number(item.maximum.to_double()),
    }),
  )
}
