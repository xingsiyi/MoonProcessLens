///|
test "events detach caller arrays and preserve exact integer values" {
  let fields = [{ name: "id", value: Integer(9007199254740993L), }]
  let event = Event::new("e1", "entity", 10L, "created", fields~)
  fields.clear()
  assert_eq(event.fields().length(), 1)
  assert_eq(event.field("id"), Some(Integer(9007199254740993L)))
  assert_true(
    !Integer(9007199254740993L).compare(Equal, Integer(9007199254740992L)),
  )
  assert_true(!Integer(1L).compare(Equal, Decimal(1.0)))
}

///|
test "event rejects malformed identity, timestamps and duplicate fields" {
  for id in ["", "bad\nlabel"] {
    let result = Some(Event::new(id, "k", 0L, "a")) catch { _ => None }
    assert_true(result is None)
  }
  assert_true(
    (Some(Event::new("e", "k", -1L, "a")) catch { _ => None }) is None,
  )
  assert_true(
    (Some(
      Event::new("e", "k", 0L, "a", fields=[
        { name: "x", value: NullValue, },
        { name: "x", value: Boolean(false), },
      ]),
    ) catch {
      _ => None
    })
    is None,
  )
  assert_true(
    try {
      Decimal(@double.not_a_number).validate()
      false
    } catch {
      _ => true
    },
  )
}
