///|
test "log interchange roundtrips Unicode intervals and rejects ambiguous JSON" {
  let original = EventLog::new([
    LogEvent::new("😀", "订单", "审核", 0L, 9007199254740991L),
  ])
  let restored = parse_log(log_to_json(original).stringify())
  assert_eq(restored.traces()[0].events()[0], original.traces()[0].events()[0])
  for
    bad in [
      "{\"schema_version\":1,\"events\":[],\"events\":[]}", "{\"schema_version\":2,\"events\":[]}",
      "{\"schema_version\":1,\"events\":[],\"typo\":0}", "{\"schema_version\":1}",
    ] {
    assert_true(
      try {
        ignore(parse_log(bad))
        false
      } catch {
        _ => true
      },
    )
  }
  for text in ["01", "-1", "1.0", "9007199254740992", "9999999999999999", ""] {
    assert_true(
      try {
        ignore(process_timestamp(Json::string(text), "time"))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "alignment file validates complete cost and reference shape" {
  let spec = parse_alignment_spec(
    "{\"schema_version\":1,\"paths\":[{\"name\":\"standard\",\"activities\":[\"open\",\"close\"]}],\"costs\":{\"unexpected\":2,\"missing\":3}}",
  )
  assert_eq(
    example_trace(["open"]).align(spec.paths(), costs=spec.costs()).cost,
    3,
  )
  assert_true(
    try {
      ignore(parse_alignment_spec("{\"schema_version\":1,\"paths\":[]}"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(parse_alignment_cost(Json::number(1.5), "cost"))
      false
    } catch {
      _ => true
    },
  )
}
