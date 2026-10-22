///|
test "limits reject disabled and excessive resource budgets" {
  Limits::default().validate()
  for bad in [
    { ..Limits::default(), buffered_events: 0 },
    { ..Limits::default(), active_states: -1 },
    { ..Limits::default(), partitions: 100001 },
    { ..Limits::default(), outputs_per_call: 0 },
    { ..Limits::default(), work_per_call: 100000001 },
  ] {
    assert_true(try { bad.validate(); false } catch { _ => true })
  }
}

///|
test "work charge fails before arithmetic can overflow" {
  let work = Work::{ used: 8, limit: 10 }
  work.charge(amount=2)
  assert_eq(work.used, 10)
  assert_true(try { work.charge(); false } catch { _ => true })
  assert_eq(work.used, 10)
}
