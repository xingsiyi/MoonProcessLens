# Resource and complexity model

Let B be buffered events, S active branches, K active entity keys, P patterns,
N events released by one advance, Q temporary match candidates and M selected
outputs. Let F be the cost of a predicate evaluation including field lookup and
text comparison; let L cover copied capture metadata, bounded by 128 events and
32 stages per assignment.

- Push is O(log B) heap work and stores one event reference.
- Advance starts with O(B+S) transaction copies/index construction. Only the
  current key's branches are visited for one input event, at roughly
  O((S_key+P)F + S_key L), plus heap operations and state deduplication.
- A versioned deadline heap expires due partitions without scanning every key
  for every event. Updating a key scans its branches to find its next deadline.
  Stale heap entries are discarded by generation. The temporary heap is bounded
  by initial keys and per-input updates within the call.
- Candidate sorting costs O(Q log Q). Skip policies can additionally compare
  candidates/states against prior selected outputs; worst-case selection is
  quadratic in these bounded populations. NoSkip bypasses that scan.
- Final result sorting is O(M log M); key-order materialization is O(K log K).
- State memory includes O(B+S L), transaction copies, candidate/output captures,
  and deadline entries. Shared immutable Events avoid copying business fields
  for each transition, but capture arrays still carry a real per-branch cost.

SkipAny intentionally enumerates alternative subsequences; their number can be
exponential in input length. Finite repetition and window bounds do not make
that output size polynomial. Resource errors preserve the prior committed state.
Budgets are not a hard CPU-time or allocated-byte sandbox. Predicate/text costs,
sorting and host overhead still matter; choose limits for the actual workload.

Default maxima per engine are 4096 buffered events, 8192 active states, 1024 keys,
4096 selected outputs and 1,000,000 charged work units per advance. Work units
count explicit recognition/expiry bookkeeping. Condition AST and field/text
limits bound individual operations separately. Candidate storage uses the state
quota; discarded candidates do not consume the selected-output quota.

Session journals add O(J) retained command history. Persistent import replays it
and enforces a total restore-work limit. Monitor commits new journal suffixes
instead of copying the complete history on each chunk; staging still clones the
current bounded recognition state for transaction isolation.

The benchmark `moon run --target native --release examples/performance` processes
100,000 events in 500 independent-key pairs per batch, yielding 50,000 matches.
It asserts the output and prints elapsed milliseconds and charged work. It is a
reproducible workload, not a general throughput guarantee or a comparison with
Flink. Small combinatorial patterns can cost far more than this fixed sequence.

A shared capture-buffer representation or indexed after-match selection could
reduce copies and skip scans. They add reference-lifetime and indexing invariants;
retain the simpler bounded implementation until measurements of a real consumer
show those costs dominate.
