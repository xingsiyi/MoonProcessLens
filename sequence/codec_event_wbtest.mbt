///|
fn codec_event_failure(text : String) -> String {
  try {
    let _ = parse_event(text)
    ""
  } catch {
    err => err.message()
  }
}

///|
fn codec_scalar_failure(value : Json) -> String {
  try {
    let _ = value_from_json(value)
    ""
  } catch {
    err => err.message()
  }
}

///|
test "event JSON preserves scalar tags and exact full-range integers" {
  let event = Event::new(
    "event-😀",
    "租户/用户",
    9007199254740991L,
    "created",
    fields=[
      { name: "a_min", value: Integer(-9223372036854775808L), },
      { name: "b_max", value: Integer(9223372036854775807L), },
      { name: "c_exact", value: Integer(9007199254740993L), },
      { name: "d_decimal", value: Decimal(1.25), },
      { name: "e_text", value: Text("tab\tnewline\nquote\"😀"), },
      { name: "f_true", value: Boolean(true), },
      { name: "g_false", value: Boolean(false), },
      { name: "h_null", value: NullValue, },
    ],
  )
  let text = format_event(event)
  let decoded = parse_event(text)
  assert_eq(decoded.id(), event.id())
  assert_eq(decoded.key(), event.key())
  assert_eq(decoded.time(), event.time())
  assert_eq(decoded.kind(), event.kind())
  for field in event.fields() {
    assert_eq(decoded.field(field.name), Some(field.value))
  }
  assert_true(text.contains("\"9223372036854775807\""))
  assert_true(text.contains("\"9007199254740993\""))
  assert_eq(event_to_json(decoded), event_to_json(event))
}

///|
test "event codec accepts an omitted empty field object" {
  let event = parse_event(
    "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\"}",
  )
  assert_eq(event.fields().length(), 0)
  assert_eq(event.time(), 0L)
  assert_eq(parse_event(format_event(event)), event)
}

///|
test "integer codec accepts canonical extrema without floating conversion" {
  for
    number in [
      -9223372036854775808L, -9007199254740993L, -1L, 0L, 1L, 9007199254740993L,
      9223372036854775807L,
    ] {
    assert_eq(value_from_json(value_to_json(Integer(number))), Integer(number))
  }
}

///|
test "integer codec rejects noncanonical forms and signed overflow" {
  for
    text in [
      "", "+1", "01", "-01", "-0", "-", " 1", "1 ", "1.0", "1e2", "１", "9223372036854775808",
      "-9223372036854775809", "100000000000000000000",
    ] {
    assert_true(
      codec_scalar_failure({ "type": "integer", "value": Json::string(text) }).contains(
        "value.value",
      ),
    )
  }
  assert_true(
    codec_scalar_failure({ "type": "integer", "value": Json::number(1.0) }).contains(
      "expected string",
    ),
  )
}

///|
test "timestamps require canonical strings and the safe timestamp range" {
  for time in ["-1", "9007199254740992", "-0", "01", "+1"] {
    let text = "{\"id\":\"e\",\"key\":\"k\",\"time\":\"" +
      time +
      "\",\"kind\":\"a\"}"
    assert_true(codec_event_failure(text).contains("event.time"))
  }
  assert_true(
    codec_event_failure(
      "{\"id\":\"e\",\"key\":\"k\",\"time\":1,\"kind\":\"a\"}",
    ).contains("event.time"),
  )
}

///|
test "strict objects reject unknown keys at event and scalar paths" {
  assert_true(
    codec_event_failure(
      "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\",\"typo\":false}",
    ).contains("event.typo"),
  )
  assert_true(
    codec_event_failure(
      "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\",\"fields\":{\"score\":{\"type\":\"integer\",\"value\":\"1\",\"extra\":0}}}",
    ).contains("event.fields[\"score\"].extra"),
  )
  assert_true(
    codec_scalar_failure({ "type": "null", "value": Json::null() }).contains(
      "unknown property",
    ),
  )
}

///|
test "duplicate keys including escaped aliases are rejected before decoding" {
  for
    text in [
      "{\"id\":\"first\",\"id\":\"second\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\"}",
      "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\",\"fields\":{\"x\":{\"type\":\"integer\",\"value\":\"1\"},\"x\":{\"type\":\"integer\",\"value\":\"2\"}}}",
      "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\",\"fields\":{\"x\":{\"type\":\"text\",\"value\":\"first\",\"\\u0076alue\":\"second\"}}}",
    ] {
    assert_true(codec_event_failure(text).contains("json"))
  }
}

///|
test "wrong shapes and missing properties carry field paths" {
  assert_true(codec_event_failure("[]").contains("event"))
  assert_true(codec_event_failure("{}").contains("event.id"))
  assert_true(
    codec_event_failure(
      "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\",\"fields\":[]}",
    ).contains("event.fields"),
  )
  assert_true(
    codec_event_failure(
      "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\",\"fields\":{\"x\":{\"type\":\"boolean\",\"value\":\"true\"}}}",
    ).contains("event.fields[\"x\"].value"),
  )
  assert_true(
    codec_event_failure(
      "{\"id\":\"e\",\"key\":\"k\",\"time\":\"0\",\"kind\":\"a\",\"fields\":{\"x\":{\"type\":\"decimal\",\"value\":\"1.5\"}}}",
    ).contains("event.fields[\"x\"].value"),
  )
  assert_true(codec_scalar_failure({ "type": "text" }).contains("value.value"))
}

///|
test "decimal codec rejects nonfinite JSON values and unsafe raw scalars" {
  assert_true(
    codec_scalar_failure({
      "type": "decimal",
      "value": Json::number(@double.infinity),
    }).contains("finite"),
  )
  assert_true(
    codec_scalar_failure({
      "type": "decimal",
      "value": Json::number(@double.not_a_number),
    }).contains("finite"),
  )
  assert_true(
    codec_scalar_failure(Json::string("raw")).contains("expected object"),
  )
  assert_true(
    codec_scalar_failure(Json::number(1.0)).contains("expected object"),
  )
  assert_eq(
    value_from_json({ "type": "decimal", "value": Json::number(-0.0) }),
    Decimal(-0.0),
  )
}

///|
test "text and field counts are bounded at decode time" {
  let too_long = String::make(4097, 'x')
  assert_true(
    codec_scalar_failure({ "type": "text", "value": Json::string(too_long) }).contains(
      "4096",
    ),
  )
  let object : Map[String, Json] = Map([])
  for i in 0..<129 {
    object["f\{i}"] = { "type": "null" }
  }
  let value : Json = {
    "id": "e",
    "key": "k",
    "time": "0",
    "kind": "a",
    "fields": Json::object(object),
  }
  assert_true(
    try {
      let _ = event_from_json(value)
      false
    } catch {
      _ => true
    },
  )
}

///|
test "text parser rejects excess input depth trailing data and truncation" {
  assert_true(
    codec_event_failure(String::make(1048577, ' ')).contains("1048576"),
  )
  let nested = String::make(33, '[') + "0" + String::make(33, ']')
  assert_true(codec_event_failure(nested).contains("json"))
  assert_true(codec_event_failure("{} {}").contains("json"))
  assert_true(codec_event_failure("{").contains("json"))
}

///|
test "checked event formatter accounts for escaped text size" {
  let ordinary = Event::new("e", "k", 0L, "a")
  assert_eq(parse_event(checked_format_event(ordinary)), ordinary)
  let fields : Array[Field] = []
  for i in 0..<128 {
    fields.push({ name: "f\{i}", value: Text(String::make(4096, '\u{0001}')), })
  }
  let escaped = Event::new("escaped", "k", 0L, "a", fields~)
  assert_true(format_event(escaped).length() > 1048576)
  assert_true(
    try {
      let _ = checked_format_event(escaped)
      false
    } catch {
      _ => true
    },
  )
}
