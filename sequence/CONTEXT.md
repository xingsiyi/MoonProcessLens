# MoonCEP domain language

MoonCEP recognizes patterns in events that have already occurred.

## Language

**Event**:
An identified business observation carrying an entity key, event time, kind and scalar fields.

**Pattern**:
A named description of an event sequence, its allowed elapsed time and match selection policy.

**Stage**:
A named positive event requirement with a predicate and occurrence bounds.

**Capture**:
The ordered events assigned to one stage in a partial or complete match.

**Watermark**:
A caller declaration that the stream prefix through a given event time is closed.

**Match**:
A complete assignment of distinct stream positions to a pattern's named captures.

**Absence**:
A requirement that a forbidden event does not occur after the positive sequence and through its deadline.

**Partition**:
The observations sharing one entity key; events in different partitions never form one match.
