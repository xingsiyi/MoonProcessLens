# API and ownership guide

Import `JSJ222/mooncep` under an alias such as `cep`. Generated public signatures
are in `pkg.generated.mbti`; this page explains the interfaces' responsibilities.

| Interface | Responsibility |
| --- | --- |
| Event, Value, Field | Validated immutable observations; full-range Int64 scalar values. |
| Condition | Bounded, typed predicates; evaluate validates standalone mutable AST inputs. |
| Stage, Pattern | Deeply own condition arrays and validate capture references. |
| Engine | Own buffered input, active assignments, watermark and occurrence counter. |
| Batch, Match, Timeout | Detached results with named captures and stable evidence. |
| Checkpoint | Independent in-process state clone; each restore is detached. |
| Session | Atomic input journal; persistent restore validates and replays commands. |
| Program | Validated patterns, budgets and optional projection plans. |
| CommandReader, Monitor | Incremental text framing and combined ingestion transaction. |
| ProjectionPlan | Convert captures to typed alert fields with checked arithmetic. |
| DetectionMetrics | Bounded result counters and duration summaries. |

## Direct engine use

Engine.push returns the next successful occurrence ordinal. Engine.push_many is
atomic for the whole array. Engine.advance_watermark and finish return a Batch.
Use batch.matches and batch.timeouts separately; batch.work reports charged work
units and batch.processed counts observations actually released by the watermark.

Limits are readonly. After a Resource error, either advance smaller time prefixes,
or call engine.with_limits(validated_larger_limits) to produce a detached engine
for retry. Existing occupancy must fit the replacement budgets. Never silently
drop a partial branch to continue producing apparently complete results.

Engine.fork/checkpoint/preview detach all mutable arrays. Stage, Pattern and
Program constructors detach their caller arrays. Capture arrays returned by
results or frontiers can be changed without mutating recognition state.
Strings are immutable; copies share immutable content.

Engine.inspect produces occupancy summaries without business field values.
Engine.frontier returns bounded partial-match evidence and an explicit truncated
flag. next_event_time and next_deadline help a host decide when to wake up, but
do not authorize a watermark. Pattern.diagnose explains stage predicates only;
it does not assert that an event can complete the full temporal sequence.

## Stream ingestion and recovery

Monitor.ingest stages both its reader and engine, returning zero or more batches.
A malformed line, late event or budget failure rolls back the whole chunk.
Monitor.finish_input accepts a final non-newline-terminated command and normally
closes all event time. Pass close_time=false only when the host deliberately
wants a journal with pending detection state. The text reader is then closed.

Use command_chunks when splitting a complete Unicode String. Default StringView
slicing can shrink an endpoint inside a surrogate pair; advancing by the requested
offset rather than the actual view length can otherwise drop a character.
Byte streams need a correct incremental UTF-8 decoder before this text API.

Session.apply_many is atomic, including cumulative output capacity. Session's
max_commands bounds retained history. format_session stores the full bounded
journal; parse_session reconstructs state without exporting old detection results.
Restore has both a total work budget and each advance's normal engine budget.
In-process Checkpoint is faster than journal replay and has no durable wire format.

Library state has one synchronous owner. Coordinate concurrent callers externally.
The library opens no files or sockets, starts no threads and reads no wall clocks.
The file CLI is a separate adapter and does load bounded files into memory.

## Alert projections

ProjectionPlan supports key/pattern/time fields, capture count, first/last fields,
checked Integer sums, compensated Decimal sums, Decimal means and typed extrema.
Integer and Decimal aggregates never mix implicitly. Missing required fields,
type mismatches and overflow are explicit errors. Empty first/last, extrema and
means return NullValue; empty sums are zero. A failed projection does not roll
back an already committed recognition batch. Project before committing an external
sink when the application requires all-or-nothing alert delivery.

DetectionMetrics.observe is separately atomic. It counts a re-observed batch
again; use match identities and application delivery records for deduplication.
