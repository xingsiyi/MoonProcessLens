///|
fn observation(
  id : String,
  time : Int64,
  kind : String,
  temperature : Int64,
) -> @cep.Event raise {
  @cep.Event::new(id, "machine/7", time, kind, fields=[
    { name: "temperature", value: @cep.Integer(temperature), },
  ])
}

///|
fn main raise {
  let pattern = @cep.Pattern::new(
    "rising-alarm-recovered",
    [
      @cep.Stage::new(
        "alarm",
        @cep.All([
          @cep.Kind("alarm"),
          @cep.Compare("temperature", @cep.GreaterEqual, @cep.Integer(80L)),
        ]),
      ),
      @cep.Stage::new(
        "peak",
        @cep.All([
          @cep.Kind("alarm"),
          @cep.CaptureCompare(
            "temperature",
            @cep.Greater,
            "alarm",
            "temperature",
          ),
        ]),
        forbidden=@cep.Kind("shutdown"),
      ),
      @cep.Stage::new("recovery", @cep.Kind("normal")),
    ],
    60000L,
    after_match=@cep.SkipPastLast,
  )
  let plan = @cep.ProjectionPlan::new(pattern, [
    { name: "machine", projection: @cep.EntityKey, },
    {
      name: "initial_temperature",
      projection: @cep.FirstField("alarm", "temperature"),
    },
    {
      name: "peak_temperature",
      projection: @cep.FirstField("peak", "temperature"),
    },
    { name: "duration_ms", projection: @cep.Duration, },
  ])
  let program = @cep.Program::new([pattern], projections=[plan])
  let engine = program.engine()
  // Arrival order differs from event time; watermarks release the ordered data.
  ignore(
    engine.push_many([
      observation("peak", 2000L, "alarm", 95L),
      observation("start", 1000L, "alarm", 85L),
      observation("recovery", 5000L, "normal", 65L),
    ]),
  )
  let batch = engine.finish()
  assert_eq(batch.matches().length(), 1)
  let records = program.project(batch)
  assert_eq(records[0].fields[2].value, @cep.Integer(95L))
  println(@cep.alert_record_to_json(records[0]).stringify())
}
