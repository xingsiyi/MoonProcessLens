# MoonCEP

MoonCEP detects named event sequences in keyed business event streams using
event time. Its reusable MoonBit core owns neither sockets nor wall clocks.

The initial implementation is under development. The public contract and
runnable examples are added alongside each working feature.

The project targets login and fraud signals, order and delivery monitoring,
equipment event correlation, and product interaction funnels. Its focus is
bounded sequence recognition, rather than window aggregation or job execution.

Licensed under MIT. Algorithms are independently implemented; external
references and attribution will be recorded in `docs/sources.md`.
