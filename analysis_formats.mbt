///|
pub fn parse_policies(text : String) -> Array[ProcessPolicy] raise ProcessError {
  let root = process_object(parse_process_json(text), ["policies"], "policies")
  let values = process_array(process_required(root, "policies"), "policies")
  if values.length() > 256 {
    raise Capacity(resource="policies", limit=256)
  }
  let result = []
  for value in values {
    let row = process_object(
      value,
      ["id", "kind", "first", "second", "within_ms"],
      "policy",
    )
    let id = process_string(process_required(row, "id"), "policy.id")
    let first = process_string(process_required(row, "first"), "policy.first")
    let second = process_string(
      process_required(row, "second"),
      "policy.second",
    )
    let kind = process_string(process_required(row, "kind"), "policy.kind")
    let within = match row.get("within_ms") {
      None | Some(Null) => None
      Some(value) => Some(process_timestamp(value, "within_ms"))
    }
    model_require(
      kind == "response" || within is None,
      "policy",
      "within_ms only applies to response",
    )
    result.push(
      match kind {
        "response" =>
          Response(id~, trigger=first, target=second, within_ms=within)
        "precedence" => Precedence(id~, trigger=first, required=second)
        "not_coexist" => NotCoexist(id~, first~, second~)
        "separation_of_duties" => SeparationOfDuties(id~, first~, second~)
        _ => raise InvalidLog(path="policy.kind", reason="unknown policy kind")
      },
    )
  }
  // Use the same definition checks even when the caller only parses a spec.
  let _ = EventLog::new([]).check_policies(result)
  result
}

///|
pub fn cohort_comparison_to_json(result : CohortComparison) -> Json {
  let variants : Array[Json] = result.variants.map(row => {
    "activities": Json::array(row.activities.map(Json::string)),
    "before_cases": row.before_cases,
    "after_cases": row.after_cases,
  })
  {
    "before_cases": result.before_cases,
    "after_cases": result.after_cases,
    "total_variation": result.total_variation,
    "variants": Json::array(variants),
  }
}

///|
pub fn resource_handoffs_to_json(result : Array[ResourceHandoff]) -> Json {
  Json::array(
    result.map(row => {
      "source": row.source,
      "target": row.target,
      "occurrences": row.occurrences,
      "cases": row.cases,
    }),
  )
}
