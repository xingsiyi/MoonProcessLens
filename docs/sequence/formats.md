# Version 1 JSON formats

All textual parsers reject duplicate and unknown keys. Single documents and
individual command lines are bounded to 1,048,576 UTF-16 units. Event/command
parsing allows nesting depth 32; condition/pattern/program/session documents allow
128 wire levels, while the actual Condition AST is limited to depth 32 and 512
unfolded nodes. Direct Json constructors are also validated and cycles are bounded.

Event: `{id, key, time, kind, fields}`. Time is a canonical decimal String.
Fields map names to tagged scalars:

```json
{
  "amount": {"type": "integer", "value": "9007199254740993"},
  "ratio": {"type": "decimal", "value": 0.75},
  "label": {"type": "text", "value": "demo"},
  "enabled": {"type": "boolean", "value": true},
  "missing": {"type": "null"}
}
```

Integer Strings preserve the full signed Int64 range and reject leading plus,
leading zeroes, negative zero and overflow. Decimal values must be finite. Event
fields are capped at 128; each text value at 4096 UTF-16 units. format_event can
represent every valid Event; checked_format_event additionally enforces the text
parser's document-size bound.

Commands are `{type:"event",event:EVENT}` or `{type:"watermark",time:"..."}`.
NDJSON accepts LF, CRLF and blank lines. finish reads an unfinished final line.
Reader.feed errors leave its previous pending text and line number unchanged.

Pattern: `{schema_version:1,id,within,after_match,stages,absence?}`. Within is a
canonical Int64 String. Every stage has `{name,condition,min,max,contiguity,forbidden?}`.
Min/max are small JSON integers. Contiguity is strict/skip_next/skip_any; after_match
is no_skip/skip_to_next_start/skip_past_last.

Conditions use a `type` tag: always, kind, has, compare, field_compare,
capture_compare, capture_count, text_prefix, text_contains, all, any, not.
Comparison `op` tokens are eq/ne/lt/le/gt/ge. Examples and exhaustive branch
encodings are exercised in codec_pattern_wbtest.mbt.

Program: `{schema_version:1,patterns,limits,projections}`. See
`examples/files/program.json` for a complete validated configuration.
Projection column types are entity_key, pattern_name, start_time, end_time,
duration, absence, capture_size, first, last, sum_integer, sum_decimal, minimum,
maximum and average_decimal. Capture/field properties are required only by the
corresponding projection types.

Session: `{schema_version:1,patterns,limits,max_commands,commands}`. This stores
input history, not arbitrary internal branch records. Import verifies every
command and reconstructs state through the real recognizer. The journal contains
its original business fields; store it with the access controls of its inputs.
It does not coordinate external source offsets, a database transaction or a sink.

Batch JSON contains schema_version, matches, timeouts, processed and work.
Each match contains pattern/key/identity, started/ended Strings, absence, occurrence
Strings and named capture event arrays. Wire output APIs return detached Json
objects. Result identity is an exact, length-prefixed session-local string.
