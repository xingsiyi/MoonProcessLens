///|
test "preview recognizes against existing buffered input without committing" {
  let engine = Engine::new([pair_pattern()])
  input(engine, "a", 0L)
  let b = Event::new("b", "k", 1L, "b")
  let preview = engine.preview([b], 1L)
  assert_eq(preview.batch().matches().length(), 1)
  assert_eq(preview.inspection().active_states(), 0)
  assert_eq(engine.buffered(), 1)
  assert_eq(engine.watermark(), -1L)
  assert_eq(engine.inspect().occurrence(), 1L)
  assert_eq(pair_pattern().diagnose(b)[1].positive.matched(), true)
  assert_eq(engine.push(b), 2L)
}
