///|
test "XES scalar defaults apply by scope and explicit values override" {
  let log = @processlens.parse_xes(
    "<log><global scope='trace'><string key='concept:name' value='c'/></global><global scope='event'><string key='concept:name' value='default'/><date key='time:timestamp' value='1970-01-01T00:00:00Z'/></global><trace><event/><event><string key='concept:name' value='override'/><date key='time:timestamp' value='1970-01-01T00:00:01Z'/></event></trace></log>",
  )
  let events = log.traces()[0].events()
  assert_eq(log.case_count(), 1)
  assert_eq(events.length(), 2)
  assert_eq(events[0].activity, "default")
  assert_eq(events[1].activity, "override")
  assert_eq(events[1].completed, 1000L)
}

///|
test "XES duplicate default scopes cannot hide conflicting interpretations" {
  let mut rejected = false
  try {
    let _ = @processlens.parse_xes(
      "<log><global scope='event'/><global scope='event'/></log>",
    )
  } catch {
    _ => rejected = true
  }
  assert_true(rejected)
}
