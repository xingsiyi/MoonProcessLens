///|
fn main raise {
  let pattern = @cep.Pattern::new("failed-then-success", [
    @cep.Stage::new("failures", @cep.Kind("login_failed"), min=3, max=3),
    @cep.Stage::new("success", @cep.Kind("login_success")),
  ], 300000L, after_match=@cep.SkipPastLast)
  let engine = @cep.Engine::new([pattern])
  // One user's events cannot complete another user's sequence.
  let events = [
    @cep.Event::new("f1", "user/alex", 1000L, "login_failed"),
    @cep.Event::new("other", "user/sam", 2000L, "login_success"),
    @cep.Event::new("f2", "user/alex", 3000L, "login_failed"),
    @cep.Event::new("f3", "user/alex", 4000L, "login_failed"),
    @cep.Event::new("s1", "user/alex", 5000L, "login_success"),
  ]
  ignore(engine.push_many(events))
  let batch = engine.finish()
  assert_eq(batch.matches().length(), 1)
  let found = batch.matches()[0]
  assert_eq(found.events("failures").length(), 3)
  assert_eq(found.key(), "user/alex")
  println("login signal: \{found.key()} failed=\{found.events("failures").length()} success=\{found.events("success")[0].id()}")
  println(@cep.match_to_json(found).stringify())
}
