///|
fn main raise {
  let pattern = @cep.Pattern::new("unpaid-order", [
    @cep.Stage::new("order", @cep.Kind("placed")),
  ], 30000L, absence=@cep.Any([@cep.Kind("paid"), @cep.Kind("cancelled")]))
  let session = @cep.Session::new([pattern])
  ignore(session.apply(@cep.Observe(@cep.Event::new("o1", "order/100", 0L, "placed"))))
  ignore(session.apply(@cep.Observe(@cep.Event::new("o2", "order/200", 10000L, "placed"))))
  ignore(session.apply(@cep.Advance(10000L)))
  // The journal can be stored by a host. Restoring repeats detection inputs;
  // it does not commit external payments or promise sink delivery semantics.
  let restored = @cep.parse_session(@cep.format_session(session))
  ignore(restored.apply(@cep.Observe(@cep.Event::new("p2", "order/200", 40000L, "paid"))))
  let result = restored.finish()
  assert_eq(result.matches().length(), 1)
  assert_eq(result.matches()[0].key(), "order/100")
  assert_eq(result.matches()[0].ended(), 30000L)
  assert_true(result.matches()[0].is_absence())
  println("unpaid order: \{result.matches()[0].key()} deadline=\{result.matches()[0].ended()}")
  println("order/200 payment at its exact deadline cancels its absence match")
}
