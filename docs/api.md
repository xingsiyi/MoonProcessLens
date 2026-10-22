# Process analysis API

The module is `xingsiyi/processlens`. Import its root package as `lens`.

| Interface | Responsibility |
| --- | --- |
| LogEvent | Validated immutable activity interval and optional resource. |
| EventLog | Bounded, detached, case-grouped observations in deterministic order. |
| CaseTrace | A detached case history; explicit empty traces are allowed. |
| EventLog.discover | Activity/edge frequencies, case coverage, starts/ends and exact variants. |
| ReferencePath, AlignmentCosts | Owned finite comparison paths and positive missing/unexpected costs. |
| CaseTrace.align | Optimal weighted insertion/deletion explanation with event evidence. |
| EventLog.align | All case alignments with a cumulative preflight cell budget. |
| EventLog.performance | Case busy/idle/service, activity/handoff distributions and resource concurrency. |
| parse_log, log_to_json | Versioned, strict, bounded JSON interchange. |
| parse_alignment_spec | Parse reference paths and weights for file integration. |

Constructors own arrays and return copies through getters. LogEvent and constructor
configuration fields are private. Reports own mutable result arrays, so applications
may filter or annotate reports without changing the EventLog. State is synchronous
and callers coordinate concurrent access; the root library performs no IO.

The root package has no dependency on the optional `xingsiyi/processlens/sequence`
package. That package preserves the prior event pattern detector, documented under
[sequence](sequence/api.md). The root types are deliberately separate: a completed
activity interval is not the detector's point-in-time Event.
