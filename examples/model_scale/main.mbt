///|
fn percentile(values : Array[UInt64], p : Int32) -> UInt64 {
  let sorted = values.copy()
  sorted.sort_by((a, b) => a.compare(b))
  sorted[(sorted.length() * p + 99) / 100 - 1]
}

///|
fn main raise {
  let paths = [["A", "B"], ["A", "X", "B"], ["A"], ["B", "A"]]
  let events = []
  for c in 0..<2000 {
    for i, activity in paths[c % 4] {
      events.push(
        @lens.LogEvent::new(
          "e\{c}-\{i}",
          "c\{c}",
          activity,
          (i * 10).to_int64(),
          (i * 10 + 1).to_int64(),
        ),
      )
    }
  }
  let log = @lens.EventLog::new(events)
  let train = @lens.EventLog::new([
    @lens.LogEvent::new("a", "t", "A", 0L, 1L),
    @lens.LogEvent::new("b", "t", "B", 2L, 3L),
  ])
  let net = train.discover_alpha()
  let limits : @lens.ModelLimits = {
    states: 200000,
    edges: 2000000,
    tokens_per_place: 4,
  }
  let cached_ms = []
  let full_ms = []
  let mut reused = 0
  let mut cached_states = 0
  let mut full_states = 0
  for _ in 0..<10 {
    let start = @env.now()
    let cached = log.align_net(net, limits~)
    cached_ms.push(@env.now() - start)
    let start = @env.now()
    let full = log.align_net(net, limits~, reuse_variants=false)
    full_ms.push(@env.now() - start)
    reused = 0
    cached_states = 0
    full_states = 0
    for i in 0..<cached.length() {
      assert_eq(cached[i].cost, full[i].cost)
      assert_true(cached[i].moves == full[i].moves)
      assert_eq(cached[i].case_id, full[i].case_id)
      if cached[i].reused_variant {
        reused += 1
      }
      cached_states += cached[i].visited_states
      full_states += full[i].visited_states
    }
  }
  assert_eq(reused, 1996)
  let report : Json = {
    "cases": 2000,
    "events": log.event_count(),
    "variants": 4,
    "rounds": 10,
    "reused_per_round": reused,
    "cached_search_states": cached_states,
    "full_search_states": full_states,
    "cached_p50_ms": percentile(cached_ms, 50).to_double(),
    "cached_p95_ms": percentile(cached_ms, 95).to_double(),
    "uncached_p50_ms": percentile(full_ms, 50).to_double(),
    "uncached_p95_ms": percentile(full_ms, 95).to_double(),
    "cost_and_evidence_equal": true,
  }
  println(report.stringify())
}
