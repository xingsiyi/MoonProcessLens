///|
fn main raise {
  let pattern = @cep.Pattern::new(
    "checkout-funnel",
    [
      @cep.Stage::new("view", @cep.Kind("view")),
      @cep.Stage::new("coupon", @cep.Kind("coupon"), min=0),
      @cep.Stage::new(
        "purchase",
        @cep.Kind("purchase"),
        contiguity=@cep.SkipAny,
      ),
    ],
    600000L,
  )
  let metrics = @cep.DetectionMetrics::new()
  let engine = @cep.Engine::new([pattern])
  for
    (id, kind, time) in [
      ("v", "view", 0L),
      ("p1", "purchase", 100L),
      ("p2", "purchase", 200L),
    ] {
    ignore(engine.push(@cep.Event::new(id, "visit/1", time, kind)))
  }
  let preview = engine.preview([], 200L)
  assert_eq(engine.watermark(), -1L)
  assert_eq(preview.batch().matches().length(), 2)
  let actual = engine.advance_watermark(200L)
  metrics.observe(actual)
  assert_eq(metrics.series()[0].matches, 2L)
  assert_eq(actual.matches()[0].events("coupon").length(), 0)
  println(@cep.metrics_to_json(metrics).stringify())
}
