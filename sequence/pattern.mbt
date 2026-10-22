///|
/// How events not accepted by the next positive occurrence are treated.
pub(all) enum Contiguity {
  Strict
  SkipNext
  SkipAny
} derive(Eq, @debug.Debug)

///|
pub extend Contiguity with Eq::{equal, not_equal}

///|
pub extend Contiguity with @debug.Debug::{to_repr}

///|
/// Selection applied after a match has been emitted.
pub(all) enum AfterMatch {
  NoSkip
  SkipToNextStart
  SkipPastLast
} derive(Eq, @debug.Debug)

///|
pub extend AfterMatch with Eq::{equal, not_equal}

///|
pub extend AfterMatch with @debug.Debug::{to_repr}

///|
/// One named positive requirement. Construction detaches condition arrays.
pub struct Stage {
  name : String
  condition : Condition
  min : Int32
  max : Int32
  contiguity : Contiguity
  forbidden : Condition?
}

///|
pub fn Stage::new(
  name : String,
  condition : Condition,
  min~ : Int32 = 1,
  max~ : Int32 = 1,
  contiguity~ : Contiguity = SkipNext,
  forbidden? : Condition,
) -> Stage raise CepError {
  require_label(name, "stage.name")
  if min < 0 || max < 1 || min > max || max > 32 {
    raise Invalid(
      path="stage.occurrences",
      reason="expected 0 <= minimum <= maximum <= 32 and maximum >= 1",
    )
  }
  validate_condition_structure(condition)
  if forbidden is Some(exclusion) {
    validate_condition_structure(exclusion)
  }
  {
    name,
    condition: clone_condition(condition),
    min,
    max,
    contiguity,
    forbidden: clone_optional_condition(forbidden),
  }
}

///|
fn clone_optional_condition(condition : Condition?) -> Condition? {
  condition.map(clone_condition)
}

///|
fn clone_stage(stage : Stage) -> Stage {
  {
    name: stage.name,
    condition: clone_condition(stage.condition),
    min: stage.min,
    max: stage.max,
    contiguity: stage.contiguity,
    forbidden: clone_optional_condition(stage.forbidden),
  }
}

///|
pub fn Stage::name(self : Stage) -> String {
  self.name
}

///|
pub fn Stage::condition(self : Stage) -> Condition {
  clone_condition(self.condition)
}

///|
pub fn Stage::minimum(self : Stage) -> Int32 {
  self.min
}

///|
pub fn Stage::maximum(self : Stage) -> Int32 {
  self.max
}

///|
pub fn Stage::contiguity(self : Stage) -> Contiguity {
  self.contiguity
}

///|
pub fn Stage::forbidden(self : Stage) -> Condition? {
  clone_optional_condition(self.forbidden)
}

///|
pub fn Stage::is_optional(self : Stage) -> Bool {
  self.min == 0
}

///|
pub fn Stage::is_repeated(self : Stage) -> Bool {
  self.max > 1
}

///|
/// A bounded pattern with a mandatory first stage and unique capture names.
pub struct Pattern {
  id : String
  stages : Array[Stage]
  within : Int64
  after_match : AfterMatch
  absence : Condition?
}

///|
pub fn Pattern::new(
  id : String,
  stages : Array[Stage],
  within : Int64,
  after_match~ : AfterMatch = NoSkip,
  absence? : Condition,
) -> Pattern raise CepError {
  require_label(id, "pattern.id")
  if within < 1L || within > 31536000000L {
    raise Invalid(
      path="pattern.within",
      reason="expected 1..31536000000 event-time units",
    )
  }
  if stages.is_empty() {
    raise Invalid(
      path="pattern.stages",
      reason="at least one stage is required",
    )
  }
  if stages.length() > 32 {
    raise Resource(resource="pattern stages", limit=32)
  }
  if stages[0].min == 0 {
    raise Invalid(
      path="pattern.stages[0]",
      reason="the first stage must consume at least one event",
    )
  }
  let previous : Array[String] = []
  let detached : Array[Stage] = []
  let mut total = 0
  for index, stage in stages {
    if previous.contains(stage.name) {
      raise Invalid(
        path="pattern.stages[\{index}].name",
        reason="duplicate capture name \{stage.name}",
      )
    }
    stage.condition.validate(previous)
    if stage.forbidden is Some(forbidden) {
      forbidden.validate(previous)
    }
    total += stage.max
    if total > 128 {
      raise Resource(resource="pattern maximum captures", limit=128)
    }
    detached.push(clone_stage(stage))
    previous.push(stage.name)
  }
  if absence is Some(condition) {
    condition.validate(previous)
  }
  {
    id,
    stages: detached,
    within,
    after_match,
    absence: clone_optional_condition(absence),
  }
}

///|
fn clone_pattern(pattern : Pattern) -> Pattern {
  {
    id: pattern.id,
    stages: pattern.stages.map(clone_stage),
    within: pattern.within,
    after_match: pattern.after_match,
    absence: clone_optional_condition(pattern.absence),
  }
}

///|
pub fn Pattern::id(self : Pattern) -> String {
  self.id
}

///|
pub fn Pattern::stages(self : Pattern) -> Array[Stage] {
  self.stages.map(clone_stage)
}

///|
pub fn Pattern::stage(self : Pattern, name : String) -> Stage? {
  for stage in self.stages {
    if stage.name == name {
      return Some(clone_stage(stage))
    }
  }
  None
}

///|
pub fn Pattern::stage_at(self : Pattern, index : Int32) -> Stage? {
  if index < 0 || index >= self.stages.length() {
    None
  } else {
    Some(clone_stage(self.stages[index]))
  }
}

///|
pub fn Pattern::stage_names(self : Pattern) -> Array[String] {
  self.stages.map(stage => stage.name)
}

///|
pub fn Pattern::within(self : Pattern) -> Int64 {
  self.within
}

///|
pub fn Pattern::after_match(self : Pattern) -> AfterMatch {
  self.after_match
}

///|
pub fn Pattern::absence(self : Pattern) -> Condition? {
  clone_optional_condition(self.absence)
}

///|
/// Structural classification, not a guarantee on runtime candidate count.
pub(all) enum BranchingRisk {
  FixedSequence
  BoundedRepetition
  CombinatorialSelection
} derive(Eq, @debug.Debug)

///|
pub extend BranchingRisk with Eq::{equal, not_equal}

///|
pub extend BranchingRisk with @debug.Debug::{to_repr}

///|
pub(all) struct PatternAnalysis {
  minimum_captures : Int32
  maximum_captures : Int32
  nullable_stages : Int32
  variable_stages : Int32
  repeated_stages : Int32
  strict_stages : Int32
  skip_any_stages : Int32
  guarded_stages : Int32
  has_absence : Bool
  branching_risk : BranchingRisk
} derive(Eq, @debug.Debug)

///|
pub extend PatternAnalysis with Eq::{equal, not_equal}

///|
pub extend PatternAnalysis with @debug.Debug::{to_repr}

///|
pub fn Pattern::analysis(self : Pattern) -> PatternAnalysis {
  let mut minimum_captures = 0
  let mut maximum_captures = 0
  let mut nullable_stages = 0
  let mut variable_stages = 0
  let mut repeated_stages = 0
  let mut strict_stages = 0
  let mut skip_any_stages = 0
  let mut guarded_stages = 0
  for stage in self.stages {
    minimum_captures += stage.min
    maximum_captures += stage.max
    if stage.min == 0 {
      nullable_stages += 1
    }
    if stage.min != stage.max {
      variable_stages += 1
    }
    if stage.max > 1 {
      repeated_stages += 1
    }
    if stage.contiguity == Strict {
      strict_stages += 1
    }
    if stage.contiguity == SkipAny {
      skip_any_stages += 1
    }
    if stage.forbidden is Some(_) {
      guarded_stages += 1
    }
  }
  let branching_risk = if skip_any_stages > 0 || variable_stages > 1 {
    CombinatorialSelection
  } else if repeated_stages > 0 || nullable_stages > 0 {
    BoundedRepetition
  } else {
    FixedSequence
  }
  {
    minimum_captures,
    maximum_captures,
    nullable_stages,
    variable_stages,
    repeated_stages,
    strict_stages,
    skip_any_stages,
    guarded_stages,
    has_absence: self.absence is Some(_),
    branching_risk,
  }
}
