///|
test "monitor commits framing and recognition together" {
  let monitor = Monitor::new([pair_pattern()])
  let a = format_command(Observe(Event::new("a", "k", 0L, "a")))
  let b = format_command(Observe(Event::new("b", "k", 1L, "b")))
  ignore(monitor.ingest(a + "\n"))
  assert_eq(monitor.stats().accepted_events, 1L)
  assert_true(
    try {
      ignore(monitor.ingest(b + "\ninvalid\n"))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(monitor.stats().accepted_events, 1L)
  ignore(monitor.ingest(b))
  assert_eq(monitor.stats().accepted_events, 1L)
  let batches = monitor.finish_input()
  assert_eq(batches.length(), 1)
  assert_eq(batches[0].matches().length(), 1)
  assert_eq(monitor.stats().accepted_events, 2L)
  assert_eq(monitor.stats().matches, 1L)
  assert_eq(monitor.finish_input().length(), 0)
}

///|
test "monitor recognition failure rolls back already parsed lines" {
  let monitor = Monitor::new([pair_pattern()])
  let initial = format_command(Advance(2L)) + "\n"
  ignore(monitor.ingest(initial))
  let bad = format_command(Observe(Event::new("late", "k", 1L, "a"))) + "\n"
  assert_true(
    try {
      ignore(monitor.ingest(bad))
      false
    } catch {
      LateEvent(..) => true
      _ => false
    },
  )
  assert_eq(monitor.stats().accepted_events, 0L)
  assert_eq(monitor.stats().pending_text_units, 0)
  assert_eq(monitor.session().commands().length(), 1)
}
