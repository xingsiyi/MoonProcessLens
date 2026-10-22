# Complexity and resource model

Let N be events, C cases, L a case length, A distinct activities, E distinct
direct-follow edges, and R reference paths with lengths M_r.

| Operation | Time | Additional space |
| --- | --- | --- |
| Log reconstruction | O(N log N + C log C) | O(N+C) |
| Discovery | Expected O(N + A log A + E log E + variant sorting) | O(N+A+E+C) |
| Case interval union | O(L) on reconstructed order | O(1) |
| Full performance report | O(N log N + C log C), including distributions and resource sweeps | O(N+C+A+E) |
| Trace alignment | O(sum_r (L+1)(M_r+1)) | Maximum grid plus retained result moves |
| Whole-log alignment | Sum of trace grids, preflight-bounded | Returned moves plus largest candidate grid |

Discovery's length-prefixed string identities encode complete sequences; key creation,
hashing and variant tie sorting also cost their string lengths. Labels are bounded,
but this is not a claim of constant-cost arbitrary-size string operations. Variant
sorting may compare full trace identities. Map operations are expected hash costs.

Alignment defaults to 1,000,000 total grid cells, configurable up to 20,000,000.
Preflight uses Int64 before any grid allocation; grid indices and costs fit Int32
under the model limits. A grid stores Int32 costs (about 4 bytes/cell plus runtime
array overhead). Candidates are sequential; garbage collection may temporarily retain
more than one candidate allocation, so the cumulative cell cap also bounds allocated
grid storage for an operation. No timeout/CPU-byte budget or constant-memory claim.

Reports materialize complete bounded logs and distributions. This is an embedded
batch library for bounded inputs, not a billion-event streaming analytics service.
Optimize only after workload measurements: histogram approximations would change
quantile semantics, and compressed DP reconstruction would complicate evidence ties.
