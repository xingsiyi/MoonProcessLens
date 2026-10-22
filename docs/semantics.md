# Event and pattern semantics

An Event has a nonempty ID, key, kind, nonnegative Int64 event time, and named
scalar fields. IDs are metadata, not deduplication keys. Two successful pushes
of equal events are distinct occurrences. Integer and Decimal are different
types; integers are never coerced to Double for comparisons.

## Ordering and windows

An engine begins with watermark -1. Push only buffers an immutable owned event.
Advance(W) stages a transaction, processes buffered observations in increasing
`(time, successful push ordinal)` order, closes deadlines, then commits all state.
After success, any time <= W is late. A failed call commits neither popped input,
new captures, ordinals, watermark nor partial results.

Each match belongs to one key. Its global window is
`[first_captured_time, first_captured_time + within]`. A positive event at the
deadline is eligible. All observations at one timestamp are handled before
deadline expiry at that timestamp. Watermarks are caller assertions about event
completeness, not inferred from the largest timestamp or the wall clock.

Supported event times end at MAX_EVENT_TIME=9007199254740991. Windows are 1 through
MAX_WINDOW=31536000000. FINAL_WATERMARK=9007230790740991 reaches every possible
deadline; Engine.finish uses it and is idempotent in emitted results.

## Stages and contiguity

A pattern has 1..32 uniquely named stages, at most 128 captured events in total,
and a mandatory first stage. Each stage has `0 <= min <= max <= 32`, with max>=1.
Optional means min=0. There are no empty overall matches.

For each branch waiting for the next occurrence of a stage:

| Mode | Matching input | Nonmatching input |
| --- | --- | --- |
| Strict | consume | kill branch |
| SkipNext | consume the first accepted occurrence | retain branch |
| SkipAny | branch into consume and retain | retain branch |

The same mode applies when entering a stage and when repeating it. Once min is
met, the branch can proceed to the next stage; if below max it can also continue
the current stage. Optional suffixes are expanded without reusing the current
event. A single occurrence is captured at most once in one assignment.

CaptureCompare reads the last event of an earlier named capture. Empty optional
captures have count zero and no field value. Missing fields and incompatible
types compare false even under NotEqual; Not then applies ordinary Boolean
negation. Empty All is true and empty Any is false. Every AST branch is validated,
including branches that would short circuit during evaluation.

## Exclusion and absence

Stage.forbidden is tested before its positive condition on every event observed
while that branch awaits the stage or another repetition. A forbidden event
cancels that branch, even if it also satisfies the positive condition. The same
event may still start a different branch. This is an explicit exclusion guard,
not a claim of equivalence to Flink's notFollowedBy.

Pattern.absence starts observing after the complete positive sequence. It rejects
any later occurrence satisfying the absence predicate through the inclusive
global deadline. Only a watermark proving the deadline closed confirms the
absence match. Its ended time is the deadline; last_event_time remains the last
positive capture. A forbidden observation at the exact deadline cancels absence.

Timeouts report expired incomplete positive branches. They are diagnostic
prefixes, not a claim that an entity's entire process failed. One entity can have
both a completed match and other timed-out branches. Cancelled absence branches
do not become successful matches or positive timeouts.

## Match selection

Candidates completing on one occurrence are sorted by start time, first ordinal,
capture sizes and capture ordinals after pattern/key ordering. Absence candidates
also sort by deadline. Duplicate assignments are removed before selection.

- NoSkip retains all assignments.
- SkipToNextStart selects one and removes alternatives with its exact start occurrence.
- SkipPastLast selects one and removes starts at or before its last positive occurrence.

Policies are isolated by pattern and key. Selected results, rather than discarded
candidates, consume the output quota. Candidate storage has a separate bound
using active_states. Result identities are stable within the same input occurrence
order and pattern definition; they are not cryptographic hashes or globally
unique IDs across independent sessions.
