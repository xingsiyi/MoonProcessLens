# Process interchange, schema version 1

`parse_log` accepts a root object with exactly `schema_version` (numeric 1) and
`events` (an array). Each event requires string `id`, `case_id`, `activity`,
`started`, `completed`; optional `resource` is a string or null. Timestamps are
canonical nonnegative decimal strings, preserving exact values across JSON hosts.

See [a complete input](../examples/files/process-log.json). Unknown/duplicate JSON
keys, missing fields, invalid intervals and duplicate event IDs are rejected.
Text documents are limited to 16 Mi UTF-16 units with JSON nesting <=8. The root
parser does not accept the optional sequence package's NDJSON command format.
The file CLI reads each bounded file into memory; it is not a streaming reader.

`parse_alignment_spec` requires `schema_version` and `paths`, each containing
`name` and `activities`. Optional `costs` contains both integer `unexpected` and
`missing` in 1..1000. Path names are unique; activities may be empty. See
[reference input](../examples/files/reference-paths.json).

`processlens analyze LOG.json` prints two JSON documents, graph then performance.
`processlens align LOG.json REFERENCES.json` computes every case before printing
one result per case, using a cumulative default million-cell budget. Any failure
returns nonzero; no partial alignment documents are emitted on computation error.
The CLI does not implement transactional external delivery or persistent storage.
