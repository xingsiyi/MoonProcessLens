///|
fn main raise {
  let pattern = @cep.Pattern::new(
    "pair",
    [@cep.Stage::new("a", @cep.Kind("a")), @cep.Stage::new("b", @cep.Kind("b"))],
    100L,
  )
  let engine = @cep.Engine::new([pattern])
  let started = @env.now()
  let mut total_work = 0L
  let mut matches = 0
  for batch in 0..<100 {
    for key in 0..<500 {
      ignore(
        engine.push(
          @cep.Event::new("a\{batch}", "k\{key}", (batch * 2).to_int64(), "a"),
        ),
      )
      ignore(
        engine.push(
          @cep.Event::new(
            "b\{batch}",
            "k\{key}",
            (batch * 2 + 1).to_int64(),
            "b",
          ),
        ),
      )
    }
    let result = engine.advance_watermark((batch * 2 + 1).to_int64())
    matches += result.matches().length()
    total_work += result.work().to_int64()
  }
  let elapsed = @env.now() - started
  assert_eq(matches, 50000)
  assert_eq(engine.active_states(), 0)
  println(
    "events=100000 matches=\{matches} work=\{total_work} elapsed_ms=\{elapsed}",
  )
  println(
    "Work counts recognition bookkeeping, not a hard CPU or byte-memory bound.",
  )
}
