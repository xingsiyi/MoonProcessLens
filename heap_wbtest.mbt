///|
test "event heap orders time then successful arrival ordinal" {
  let heap : Array[Stamped] = []
  for (time, ordinal) in [(12L, 1L), (5L, 3L), (5L, 2L), (0L, 9L)] {
    heap_push(heap, { event: Event::new("e", "k", time, "a"), ordinal, })
  }
  let result = []
  while heap_pop(heap) is Some(item) {
    result.push(item.ordinal)
  }
  assert_eq(result, [9L, 2L, 3L, 1L])
}

///|
test "heap matches independently sorted permutation" {
  let heap : Array[Stamped] = []
  let expected : Array[(Int64, Int64)] = []
  for i in 0..<257 {
    let time = (i * 71 % 37).to_int64()
    let ordinal = i.to_int64()
    heap_push(heap, { event: Event::new("e", "k", time, "a"), ordinal, })
    expected.push((time, ordinal))
  }
  expected.sort()
  for pair in expected {
    let item = heap_pop(heap).unwrap()
    assert_eq((item.event.time, item.ordinal), pair)
  }
  assert_true(heap_pop(heap) is None)
}
