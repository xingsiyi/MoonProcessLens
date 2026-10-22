///|
fn example_trace(names : Array[String]) -> CaseTrace raise ProcessError {
  CaseTrace::new(
    "case",
    names.mapi((i, name) => {
      LogEvent::new(
        i.to_string(),
        "case",
        name,
        i.to_int64(),
        i.to_int64() + 1L,
      )
    }),
  )
}

///|
test "alignment reports missing approval and unexpected retry with evidence" {
  let trace = example_trace(["open", "retry", "pay"])
  let path = ReferencePath::new("standard", ["open", "approve", "pay"])
  let result = trace.align([path])
  assert_eq(result.cost, 2)
  assert_true(result.moves.contains(Missing(activity="approve")))
  assert_true(result.moves.contains(Unexpected(event_id="1", activity="retry")))
  assert_eq(result.evaluated_cells, 16)
  assert_true(result.fitness > 0.66 && result.fitness < 0.67)
  ignore(alignment_to_json(result).stringify())
  assert_eq(
    example_trace([]).align([ReferencePath::new("empty", [])]).fitness,
    1.0,
  )
}

///|
test "alignment budgets, reference ownership, weights and tie order" {
  let source = ["a"]
  let path = ReferencePath::new("first", source)
  source.clear()
  let trace = example_trace(["b"])
  let result = trace.align(
    [path],
    costs=AlignmentCosts::new(unexpected=3, missing=7),
  )
  assert_eq(result.cost, 10)
  assert_eq(
    trace.align([path, ReferencePath::new("second", ["a"])]).reference,
    "first",
  )
  assert_true(
    try {
      ignore(trace.align([path], max_cells=3))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(trace.align([path, path]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(AlignmentCosts::new(missing=0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(trace.align([]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "whole-log alignment has a cumulative budget including unselected references" {
  let log = EventLog::new([
    LogEvent::new("1", "a", "x", 0L, 1L),
    LogEvent::new("2", "b", "x", 0L, 1L),
  ])
  let references = [ReferencePath::new("model", ["x"])]
  assert_eq(log.align(references, max_cells=8).length(), 2)
  assert_true(
    try {
      ignore(log.align(references, max_cells=7))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(EventLog::new([]).align(references, max_cells=1).length(), 0)
}

///|
fn binary_words(length : Int32) -> Array[Array[String]] {
  let words : Array[Array[String]] = [[]]
  for size = 1; size <= length; size = size + 1 {
    let previous = words.filter(word => word.length() == size - 1)
    for word in previous {
      for symbol in ["a", "b"] {
        let next = word.copy()
        next.push(symbol)
        words.push(next)
      }
    }
  }
  words
}

///|
fn enumerated_common_length(
  left : Array[String],
  right : Array[String],
) -> Int32 {
  let mut longest = 0
  for mask = 0; mask < 1 << left.length(); mask = mask + 1 {
    let selected : Array[String] = []
    for i, symbol in left {
      if (mask & (1 << i)) != 0 {
        selected.push(symbol)
      }
    }
    let mut index = 0
    for symbol in right {
      if index < selected.length() && selected[index] == symbol {
        index = index + 1
      }
    }
    if index == selected.length() && index > longest {
      longest = index
    }
  }
  longest
}

///|
test "alignment agrees with independent exhaustive common subsequences" {
  let words = binary_words(3)
  for observed in words {
    for expected in words {
      let trace = example_trace(observed)
      let result = trace.align(
        [ReferencePath::new("model", expected)],
        costs=AlignmentCosts::new(unexpected=2, missing=3),
      )
      let common = enumerated_common_length(observed, expected)
      assert_eq(
        result.cost,
        (observed.length() - common) * 2 + (expected.length() - common) * 3,
      )
      let mut i = 0
      let mut j = 0
      let mut cost = 0
      for step in result.moves {
        match step {
          Synchronous(event_id~, activity~) => {
            assert_eq(event_id, i.to_string())
            assert_eq(activity, observed[i])
            assert_eq(activity, expected[j])
            i = i + 1
            j = j + 1
          }
          Unexpected(event_id~, activity~) => {
            assert_eq(event_id, i.to_string())
            assert_eq(activity, observed[i])
            i = i + 1
            cost = cost + 2
          }
          Missing(activity~) => {
            assert_eq(activity, expected[j])
            j = j + 1
            cost = cost + 3
          }
        }
      }
      assert_eq(i, observed.length())
      assert_eq(j, expected.length())
      assert_eq(cost, result.cost)
    }
  }
}
