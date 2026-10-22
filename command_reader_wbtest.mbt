///|
test "command framing is independent of chunk boundaries and CRLF" {
  let text = format_command(Observe(Event::new("e", "k", 0L, "中文"))) +
    "\r\n\n" +
    format_command(Advance(10L))
  let baseline = CommandReader::new()
  let expected = baseline.feed(text)
  expected.append(baseline.finish())
  for split in 0..<=text.length() {
    let reader = CommandReader::new()
    let actual = reader.feed(text[:split].to_owned())
    actual.append(reader.feed(text[split:].to_owned()))
    actual.append(reader.finish())
    assert_eq(actual, expected)
  }
}

///|
test "failed chunk leaves earlier lines and partial input uncommitted" {
  let reader = CommandReader::new()
  ignore(reader.feed("{\"type\":"))
  let old = reader.pending_units()
  assert_true(
    try {
      ignore(reader.feed("\"watermark\",\"time\":\"1\"}\ninvalid\n"))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(reader.pending_units(), old)
  assert_eq(reader.line(), 1)
  assert_eq(reader.feed("\"watermark\",\"time\":\"1\"}\n"), [Advance(1L)])
  ignore(reader.finish())
  assert_true(
    try {
      ignore(reader.feed("\n"))
      false
    } catch {
      _ => true
    },
  )
}
