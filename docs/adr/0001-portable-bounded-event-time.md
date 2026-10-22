# Portable bounded event-time pattern recognition

Use a MoonBit event-time recognition core with caller-driven watermarks and finite repetition bounds. A distributed runtime would add deployment and fault-tolerance obligations before the sequence semantics could be independently verified. The library therefore exposes explicit state and work limits and returns an error atomically when a call cannot complete within them.
