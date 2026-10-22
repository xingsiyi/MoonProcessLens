///|
test "session journal commits together with engine progress" {
  let session = Session::new([pair_pattern()])
  ignore(session.apply(Observe(Event::new("a", "k", 0L, "a"))))
  ignore(session.apply(Advance(0L)))
  assert_eq(session.commands().length(), 2)
  assert_true(try { ignore(session.apply(Observe(Event::new("late", "k", 0L, "b")))); false } catch { _ => true })
  assert_eq(session.commands().length(), 2)
  assert_eq(session.active_states(), 1)
}

///|
test "journal batch failure rolls back earlier accepted commands" {
  let session = Session::new([pair_pattern()], max_commands=3)
  assert_true(try {
    ignore(session.apply_many([Observe(Event::new("a", "k", 0L, "a")), Advance(0L), Observe(Event::new("late", "k", 0L, "b"))])); false
  } catch { _ => true })
  assert_eq(session.commands().length(), 0)
  assert_eq(session.buffered(), 0)
  assert_eq(session.watermark(), -1L)
}

///|
test "journal capacity cannot be bypassed by a multi command call" {
  let session = Session::new([pair_pattern()], max_commands=1)
  ignore(session.apply(Observe(Event::new("a", "k", 0L, "a"))))
  assert_true(try { ignore(session.finish()); false } catch { Resource(..) => true; _ => false })
  assert_eq(session.buffered(), 1)
}
