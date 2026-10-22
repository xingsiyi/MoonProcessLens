///|
test "command framing is independent of chunk boundaries and CRLF" {
  let text = format_command(Observe(Event::new("e", "k", 0L, "中文😀"))) +
    "\r\n\n" +
    format_command(Advance(10L))
  let baseline = CommandReader::new()
  let expected = baseline.feed(text)
  expected.append(baseline.finish())
  for split in 0..<=text.length() {
    let reader = CommandReader::new()
    let prefix = text.clamped_view(end=split)
    let actual = reader.feed(prefix.to_owned())
    actual.append(reader.feed(text[prefix.length():].to_owned()))
    actual.append(reader.finish())
    assert_eq(actual, expected)
  }
}

///|
test "Unicode-safe chunk iterator preserves every scalar and always progresses" {
  let text = "a😀中𝄞z"
  for size in 1..<=text.length() {
    let builder = StringBuilder()
    for part in command_chunks(text, max_units=size) {
      assert_true(part.length() >= 1)
      assert_true(part.length() <= size.max(2))
      builder.write_view(part)
    }
    assert_eq(builder.to_string(), text)
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
