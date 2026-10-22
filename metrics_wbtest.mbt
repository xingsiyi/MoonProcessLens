///|
test "result metrics preserve exact counts and distinguish timeouts" {
  let engine = Engine::new([pair_pattern()])
  input(engine, "a", 0L)
  input(engine, "b", 3L)
  input(engine, "a", 4L, key="other")
  let metrics = DetectionMetrics::new()
  metrics.observe(engine.finish())
  let row = metrics.series()[0]
  assert_eq(row.matches, 1L)
  assert_eq(row.timeouts, 1L)
  assert_eq(row.mean_duration, Some(3.0))
  assert_eq(metrics.processed(), 3L)
  let detached = metrics.fork()
  metrics.reset()
  assert_eq(detached.series()[0].matches, 1L)
  assert_eq(metrics.series().length(), 0)
}

///|
test "telemetry cardinality errors do not partially record a batch" {
  let engine = Engine::new([pair_pattern()])
  input(engine, "a", 0L, key="first")
  input(engine, "a", 0L, key="second")
  input(engine, "b", 1L, key="first")
  input(engine, "b", 1L, key="second")
  let metrics = DetectionMetrics::new(max_series=1, by_key=true)
  assert_true(
    try {
      metrics.observe(engine.finish())
      false
    } catch {
      Resource(..) => true
      _ => false
    },
  )
  assert_eq(metrics.batches(), 0L)
  assert_eq(metrics.series().length(), 0)
}
