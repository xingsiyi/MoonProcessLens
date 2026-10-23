# MoonProcessLens domain language

MoonProcessLens analyses observed activity histories to describe actual process paths,
explain deviations from reference paths and measure elapsed work and waiting.

## Language

**Log event**:
A completed activity occurrence with its identity, case, activity label, interval and optional resource.

**Case**:
One business process instance, such as an order, ticket, repair job or pipeline run.

**Trace**:
The ordered activity occurrences belonging to one case.

**Directly-follows relation**:
Two adjacent activities in an observed trace; adjacency alone does not establish causality.

**Variant**:
An exact activity-label sequence shared by one or more observed cases, including repeated labels.

**Reference path**:
A finite, named activity sequence representing an accepted or comparison process variant.

**Reference-path alignment**:
A minimum-cost explanation connecting an observed trace to a reference path through synchronous, unexpected and missing activities.

**Accepting Petri net**:
A place/transition process model with explicit initial and final token markings, describing permitted activity executions including concurrency and loops.
_Avoid_: directly-follows graph, reference path

**Marking**:
The tokens currently present at each place in a Petri net.
_Avoid_: activity sequence, node status

**Silent transition**:
A model step that changes the marking without representing an observed business activity.
_Avoid_: missing event, empty activity

**Model alignment**:
A minimum-cost explanation connecting a whole trace to an accepting model execution through synchronous, log-only and model-only steps.
_Avoid_: reference-path alignment, token-replay fitness

**Alpha discovery**:
The classical causal-footprint discovery method that constructs Petri net places from maximal independent activity sets.
_Avoid_: DFG rendering, Inductive Miner

**Prefix-net discovery**:
A model of exactly the finite observed trace language with common prefixes shared and repeated activities retained as distinct occurrences.
_Avoid_: generalised loop discovery

**Lifecycle pair**:
A matched start and completion of the same activity occurrence in a case, distinguished by its instance identity when overlaps exist.
_Avoid_: adjacent events, arbitrary FIFO match

**Cohort**:
A selection of complete cases belonging to an analysis population, without truncating their histories.
_Avoid_: sliced event window

**Policy outcome**:
The satisfied, violated, inconclusive or not-applicable evidence for a declarative business rule on one case.
_Avoid_: universal process correctness

**Service work**:
The sum of activity durations, including work performed concurrently.

**Busy union**:
The elapsed time covered by at least one activity interval in a case.

**Idle time**:
The case's elapsed cycle time outside the union of its observed activity intervals.

**Resource concurrency**:
The maximum number of simultaneously observed positive-duration activities attributed to a resource.
