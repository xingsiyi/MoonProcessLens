///|
pub(all) enum Projection {
  EntityKey
  PatternName
  StartTime
  EndTime
  Duration
  AbsenceMatch
  CaptureSize(String)
  FirstField(String, String)
  LastField(String, String)
  TotalInteger(String, String)
  TotalDecimal(String, String)
  MinimumField(String, String)
  MaximumField(String, String)
  AverageDecimal(String, String)
} derive(Eq, @debug.Debug)

///|
pub extend Projection with Eq::{equal, not_equal}

///|
pub extend Projection with @debug.Debug::{to_repr}

///|
pub(all) struct Column {
  name : String
  projection : Projection
}

///|
pub struct ProjectionPlan {
  pattern : String
  columns : Array[Column]
}

///|
fn projection_capture(projection : Projection) -> String? {
  match projection {
    CaptureSize(name)
    | FirstField(name, _)
    | LastField(name, _)
    | TotalInteger(name, _)
    | TotalDecimal(name, _)
    | MinimumField(name, _)
    | MaximumField(name, _)
    | AverageDecimal(name, _) => Some(name)
    _ => None
  }
}

///|
fn projection_field(projection : Projection) -> String? {
  match projection {
    FirstField(_, field)
    | LastField(_, field)
    | TotalInteger(_, field)
    | TotalDecimal(_, field)
    | MinimumField(_, field)
    | MaximumField(_, field)
    | AverageDecimal(_, field) => Some(field)
    _ => None
  }
}

///|
pub fn ProjectionPlan::new(
  pattern : Pattern,
  columns : Array[Column],
) -> ProjectionPlan raise CepError {
  if columns.is_empty() || columns.length() > 128 {
    raise Invalid(path="projection.columns", reason="expected 1..128 columns")
  }
  let seen : Map[String, Bool] = Map([])
  let names = pattern.stages.map(stage => stage.name)
  for column in columns {
    require_label(column.name, "projection.column")
    if seen.contains(column.name) {
      raise Invalid(
        path="projection.columns",
        reason="duplicate output column \{column.name}",
      )
    }
    seen.set(column.name, true)
    if projection_capture(column.projection) is Some(name) &&
      !names.contains(name) {
      raise Invalid(path="projection.capture", reason="unknown stage \{name}")
    }
    if projection_field(column.projection) is Some(field) {
      require_label(field, "projection.field")
    }
  }
  { pattern: pattern.id, columns: columns.copy(), }
}

///|
pub fn ProjectionPlan::columns(self : ProjectionPlan) -> Array[Column] {
  self.columns.copy()
}

///|
fn projected_events(
  value : Match,
  name : String,
) -> Array[Event] raise CepError {
  for capture in value.captures {
    if capture.name == name {
      return capture.events
    }
  }
  raise Invalid(path="projection.capture", reason="match has no stage \{name}")
}

///|
fn projected_field(event : Event, field : String) -> Value raise CepError {
  match event.field(field) {
    Some(value) => value
    None =>
      raise Invalid(
        path="projection.field",
        reason="event \{event.id} lacks field \{field}",
      )
  }
}

///|
fn checked_integer_sum(left : Int64, right : Int64) -> Int64 raise CepError {
  if (right > 0L && left > 9223372036854775807L - right) ||
    (right < 0L && left < -9223372036854775808L - right) {
    raise Invalid(path="projection.sum", reason="Int64 sum overflows")
  }
  left + right
}

///|
fn project_aggregate(
  projection : Projection,
  events : Array[Event],
  field : String,
) -> Value raise CepError {
  match projection {
    TotalInteger(_, _) => {
      let mut sum = 0L
      for event in events {
        match projected_field(event, field) {
          Integer(value) => sum = checked_integer_sum(sum, value)
          _ =>
            raise Invalid(
              path="projection.sum",
              reason="integer sum requires only Integer values",
            )
        }
      }
      Integer(sum)
    }
    TotalDecimal(_, _) | AverageDecimal(_, _) => {
      let mut sum = 0.0
      let mut compensation = 0.0
      let mut mean = 0.0
      let mut count = 0
      for event in events {
        let value = match projected_field(event, field) {
          Decimal(value) => value
          _ =>
            raise Invalid(
              path="projection.sum",
              reason="decimal aggregate requires only Decimal values",
            )
        }
        count += 1
        if projection is AverageDecimal(_, _) {
          let weight = 1.0 / count.to_double()
          mean = (1.0 - weight) * mean + weight * value
          if !finite(mean) {
            raise Invalid(
              path="projection.mean",
              reason="decimal mean overflows",
            )
          }
        } else {
          let corrected = value - compensation
          let next = sum + corrected
          if !finite(corrected) || !finite(next) {
            raise Invalid(path="projection.sum", reason="decimal sum overflows")
          }
          compensation = next - sum - corrected
          sum = next
        }
      }
      if projection is AverageDecimal(_, _) {
        if count == 0 {
          NullValue
        } else {
          Decimal(mean)
        }
      } else {
        Decimal(sum)
      }
    }
    MinimumField(_, _) | MaximumField(_, _) => {
      let mut best : Value? = None
      for event in events {
        let value = projected_field(event, field)
        match best {
          None =>
            match value {
              Integer(_) | Decimal(_) | Text(_) => best = Some(value)
              _ =>
                raise Invalid(
                  path="projection.extremum",
                  reason="expected ordered scalar",
                )
            }
          Some(current) => {
            if current.type_name() != value.type_name() {
              raise Invalid(
                path="projection.extremum",
                reason="mixed value types",
              )
            }
            let comparison = if projection is MinimumField(_, _) {
              Less
            } else {
              Greater
            }
            if value.compare(comparison, current) {
              best = Some(value)
            }
          }
        }
      }
      best.unwrap_or(NullValue)
    }
    _ => raise Invalid(path="projection", reason="not an aggregate projection")
  }
}

///|
fn project_value(
  projection : Projection,
  value : Match,
) -> Value raise CepError {
  match projection {
    EntityKey => Text(value.key)
    PatternName => Text(value.pattern)
    StartTime => Integer(value.started)
    EndTime => Integer(value.ended)
    Duration => Integer(value.ended - value.started)
    AbsenceMatch => Boolean(value.absence)
    CaptureSize(name) =>
      Integer(projected_events(value, name).length().to_int64())
    FirstField(name, field) | LastField(name, field) => {
      let events = projected_events(value, name)
      if events.is_empty() {
        return NullValue
      }
      let index = if projection is FirstField(_, _) {
        0
      } else {
        events.length() - 1
      }
      projected_field(events[index], field)
    }
    _ => {
      let name = projection_capture(projection).unwrap()
      let field = projection_field(projection).unwrap()
      project_aggregate(projection, projected_events(value, name), field)
    }
  }
}

///|
pub fn ProjectionPlan::apply(
  self : ProjectionPlan,
  value : Match,
) -> Array[Field] raise CepError {
  if value.pattern != self.pattern {
    raise Invalid(
      path="projection.pattern",
      reason="match belongs to another pattern",
    )
  }
  self.columns.map(column => {
    name: column.name,
    value: project_value(column.projection, value),
  })
}
