# Process semantics and limits

LogEvent IDs must be globally unique within a log. Labels are nonempty, bounded
to 256 UTF-16 units and exclude ASCII controls. All intervals satisfy
`0 <= started <= completed <= 9007199254740991`. Units are caller-selected and
must be consistent. Zero-duration events remain in paths but consume no time.

EventLog sorts case IDs lexically, and each case by start, completion, then original
input occurrence. It accepts unordered input. Equal-time order is a documented
convention, not proof of causal order. Default limits are 100,000 events, 10,000
cases and 4,096 events/case; configurable maxima are 1,000,000, 100,000 and 10,000.
An empty EventLog contains no cases; CaseTrace.new can represent an explicit empty case.

Discovery counts occurrences and distinct-case coverage separately. Each nonempty
trace contributes one start and one end. Loops and repeated edges remain visible;
variants use exact sequences, with frequency descending then length-prefixed lexical
identity order. Graph results describe this ordering; they infer neither causality,
parallel gateways nor an executable workflow. Minimum-frequency filtering returns
edges only; all observed nodes remain in the original map.

Alignment minimizes missing-reference and unexpected-observation costs over all
given finite reference paths. Costs are positive integers <=1,000. There is no
substitution move: changing an activity requires a missing and an unexpected move.
The selected path minimizes absolute cost; equal-cost paths follow caller order.
Backtracking ties prefer synchronous, unexpected, then missing. Fitness is
`1 - cost / (observed_length*unexpected + model_length*missing)`; empty/empty is 1.
Fitness is relative to the selected reference, not a calibrated compliance score.
Loops must be explicitly represented in reference paths. This is trace-to-trace
alignment, not full Petri-net/BPMN conformance. Max 128 paths, 4,096 labels/path;
the cell budget counts all candidate grids, including rejected reference paths.
Whole-log alignment preflights the cumulative budget before computing results.

Case cycle time spans earliest start to latest completion. Busy union merges all
case intervals; idle = cycle - union. Service work sums interval durations as Double
and may exceed elapsed time; it is approximate for very large totals. Durations,
union and idle use exact Int64. Handoff gaps compare adjacent events and clamp
overlap to zero while counting overlapping pairs separately; this descriptive gap
can differ from whole-case idle if an earlier activity is still running.

Resource concurrency uses half-open positive intervals `[start,end)`, processing
ends before starts at equal timestamps. Missing resources are omitted. Without
availability calendars/capacity there is no claim of resource utilization. Duration
median/p95 use nearest-rank order statistics, and empty summaries contain null.
Reported means are Double. Concurrency and rework describe observations, not causes.

The library does not execute business actions, discover a sound Petri net, parse XES
or OCEL standards, normalize timezone/calendar conventions, infer missing lifecycle
pairs, or provide distributed/online incremental processing.
