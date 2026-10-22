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

**Alignment**:
A minimum-cost explanation connecting an observed trace to a reference path through synchronous, unexpected and missing activities.

**Service work**:
The sum of activity durations, including work performed concurrently.

**Busy union**:
The elapsed time covered by at least one activity interval in a case.

**Idle time**:
The case's elapsed cycle time outside the union of its observed activity intervals.

**Resource concurrency**:
The maximum number of simultaneously observed positive-duration activities attributed to a resource.
