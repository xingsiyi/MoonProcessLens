///|
// Independent exhaustive subsequence oracle: enumerate index assignments,
// rather than interpreting the engine's Branch states or epsilon expansion.
fn reference_assign(
  events : Array[Event],
  pattern : Pattern,
  stage : Int,
  selected : Array[Array[Int]],
  next : Int,
  count : Int,
  first : Int,
  output : Map[String, Bool],
) -> Unit {
  if stage == pattern.stages.length() {
    let builder = StringBuilder()
    for indices in selected {
      builder.write_string("\{indices.length()}:")
      for index in indices { builder.write_string("\{index + 1},") }
      builder.write_string(";")
    }
    output.set(builder.to_string(), true)
    return
  }
  let requirement = pattern.stages[stage]
  if count >= requirement.min {
    reference_assign(events, pattern, stage + 1, selected, next, 0, first, output)
  }
  if count == requirement.max { return }
  for index in next..<events.length() {
    if events[index].time - events[first].time > pattern.within { break }
    let accepted = requirement.condition.evaluate_unchecked(events[index], [])
    if accepted {
      let chosen = selected.map(indices => indices.copy())
      chosen[stage].push(index)
      reference_assign(events, pattern, stage, chosen, index + 1, count + 1, first, output)
    }
    if requirement.contiguity == Strict || (accepted && requirement.contiguity == SkipNext) { break }
  }
}

///|
fn reference_matches(events : Array[Event], pattern : Pattern) -> Array[String] {
  let output : Map[String, Bool] = Map([])
  for start in 0..<events.length() {
    if pattern.stages[0].condition.evaluate_unchecked(events[start], []) {
      let selected : Array[Array[Int]] = pattern.stages.map(_ => [])
      selected[0].push(start)
      reference_assign(events, pattern, 0, selected, start + 1, 1, start, output)
    }
  }
  let result = output.keys().collect()
  result.sort()
  result
}

///|
fn observed_assignment(value : Match) -> String {
  let builder = StringBuilder()
  let mut offset = 0
  for capture in value.captures {
    builder.write_string("\{capture.events.length()}:")
    for _ in capture.events {
      builder.write_string("\{value.occurrences[offset]},")
      offset += 1
    }
    builder.write_string(";")
  }
  builder.to_string()
}

///|
test "NFA agrees with exhaustive assignment oracle on short event alphabets" {
  for length in 0..=5 {
    let mut combinations = 1
    for _ in 0..<length { combinations *= 3 }
    for code in 0..<combinations {
      let mut digits = code
      let events : Array[Event] = []
      for i in 0..<length {
        let kind = ["a", "b", "x"][digits % 3]
        digits /= 3
        events.push(Event::new("e\{i}", "k", i.to_int64(), kind))
      }
      for first_mode in [Strict, SkipNext, SkipAny] {
        for next_mode in [Strict, SkipNext, SkipAny] {
          let pattern = Pattern::new("oracle", [
            Stage::new("a", Kind("a"), min=1, max=2, contiguity=first_mode),
            Stage::new("optional", Kind("x"), min=0, max=1, contiguity=next_mode),
            Stage::new("b", Kind("b"), contiguity=next_mode),
          ], 3L)
          let engine = Engine::new([pattern])
          ignore(engine.push_many(events))
          let actual = engine.finish().matches().map(observed_assignment)
          actual.sort()
          assert_eq(actual, reference_matches(events, pattern))
        }
      }
    }
  }
}
