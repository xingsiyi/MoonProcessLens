///|
pub(all) struct DetectionSeries {
  pattern : String
  key : String?
  matches : Int64
  absence_matches : Int64
  timeouts : Int64
  shortest_duration : Int64?
  longest_duration : Int64?
  mean_duration : Double?
}

///|
/// Bounded result telemetry. Per-key dimensions are opt-in because their
/// cardinality usually exceeds the number of configured patterns.
pub struct DetectionMetrics {
  mut series : Map[String, DetectionSeries]
  max_series : Int32
  by_key : Bool
  mut batches : Int64
  mut processed : Int64
  mut work : Int64
}

///|
pub fn DetectionMetrics::new(
  max_series~ : Int32 = 1024,
  by_key~ : Bool = false,
) -> DetectionMetrics raise CepError {
  if max_series < 1 || max_series > 100000 {
    raise Invalid(path="metrics.max_series", reason="expected 1..100000")
  }
  { series: Map([]), max_series, by_key, batches: 0L, processed: 0L, work: 0L, }
}

///|
fn metric_key(pattern : String, key : String?) -> String {
  match key {
    None => "\{pattern.length()}:\{pattern}:all"
    Some(key) => "\{pattern.length()}:\{pattern}:key:\{key.length()}:\{key}"
  }
}

///|
fn new_series(pattern : String, key : String?) -> DetectionSeries {
  {
    pattern,
    key,
    matches: 0L,
    absence_matches: 0L,
    timeouts: 0L,
    shortest_duration: None,
    longest_duration: None,
    mean_duration: None,
  }
}

///|
fn metric_row(
  rows : Map[String, DetectionSeries],
  pattern : String,
  key : String?,
  max_series : Int32,
) -> (String, DetectionSeries) raise CepError {
  let id = metric_key(pattern, key)
  match rows.get(id) {
    Some(row) => (id, row)
    None => {
      if rows.length() >= max_series {
        raise Resource(resource="metric series", limit=max_series)
      }
      (id, new_series(pattern, key))
    }
  }
}

///|
/// Observe a committed batch atomically. Re-observing a batch counts it again;
/// delivery deduplication belongs to the caller, using Match::identity.
pub fn DetectionMetrics::observe(
  self : DetectionMetrics,
  batch : Batch,
) -> Unit raise CepError {
  let rows = self.series.copy()
  for value in batch.matches {
    let key = if self.by_key { Some(value.key) } else { None }
    let (id, row) = metric_row(rows, value.pattern, key, self.max_series)
    let count = checked_integer_sum(row.matches, 1L)
    if count > 9007199254740991L {
      raise Invalid(
        path="metrics.matches",
        reason="duration mean count exceeds exact Double integer range",
      )
    }
    let duration = value.ended - value.started
    let mean = match row.mean_duration {
      Some(mean) => mean + (duration.to_double() - mean) / count.to_double()
      None => duration.to_double()
    }
    rows.set(id, {
      ..row,
      matches: count,
      absence_matches: checked_integer_sum(
        row.absence_matches,
        if value.absence {
          1L
        } else {
          0L
        },
      ),
      shortest_duration: min_optional(row.shortest_duration, duration),
      longest_duration: max_optional(row.longest_duration, duration),
      mean_duration: Some(mean),
    })
  }
  for value in batch.timeouts {
    let key = if self.by_key { Some(value.key) } else { None }
    let (id, row) = metric_row(rows, value.pattern, key, self.max_series)
    rows.set(id, { ..row, timeouts: checked_integer_sum(row.timeouts, 1L), })
  }
  let batches = checked_integer_sum(self.batches, 1L)
  let processed = checked_integer_sum(
    self.processed,
    batch.processed.to_int64(),
  )
  let work = checked_integer_sum(self.work, batch.work.to_int64())
  self.series = rows
  self.batches = batches
  self.processed = processed
  self.work = work
}

///|
pub fn DetectionMetrics::series(
  self : DetectionMetrics,
) -> Array[DetectionSeries] {
  let rows = self.series.values().collect()
  rows.sort_by((a, b) => {
    let order = a.pattern.compare(b.pattern)
    if order != 0 {
      order
    } else {
      a.key.unwrap_or("").compare(b.key.unwrap_or(""))
    }
  })
  rows
}

///|
pub fn DetectionMetrics::batches(self : DetectionMetrics) -> Int64 {
  self.batches
}

///|
pub fn DetectionMetrics::processed(self : DetectionMetrics) -> Int64 {
  self.processed
}

///|
pub fn DetectionMetrics::work(self : DetectionMetrics) -> Int64 {
  self.work
}

///|
pub fn DetectionMetrics::fork(self : DetectionMetrics) -> DetectionMetrics {
  { ..self, series: self.series.copy(), }
}

///|
pub fn DetectionMetrics::reset(self : DetectionMetrics) -> Unit {
  self.series = Map([])
  self.batches = 0L
  self.processed = 0L
  self.work = 0L
}

///|
pub fn metrics_to_json(metrics : DetectionMetrics) -> Json {
  {
    "batches": Json::string(metrics.batches.to_string()),
    "processed": Json::string(metrics.processed.to_string()),
    "work": Json::string(metrics.work.to_string()),
    "series": Json::array(
      metrics
      .series()
      .map(row => {
        "pattern": Json::string(row.pattern),
        "key": match row.key {
          Some(key) => Json::string(key)
          None => Json::null()
        },
        "matches": Json::string(row.matches.to_string()),
        "absence_matches": Json::string(row.absence_matches.to_string()),
        "timeouts": Json::string(row.timeouts.to_string()),
        "shortest_duration": optional_time_json(row.shortest_duration),
        "longest_duration": optional_time_json(row.longest_duration),
        "mean_duration": match row.mean_duration {
          Some(value) => Json::number(value)
          None => Json::null()
        },
      }),
    ),
  }
}
