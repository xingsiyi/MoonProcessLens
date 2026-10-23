# Model discovery, conformance and standard exchange

This page describes the **local 0.2.0 development version**, not the previously
published 0.1.0 API. It addresses the gap between directly-follows/path diagnostics
and executable process models. Existing DFG/reference-path/performance operations
remain available; they are not rebranded as model discovery.

## Completed workflow and representative uses

```text
XES / typed log → discover_alpha or discover_prefix_net → accepting PetriNet
BPMN / PNML / net JSON → accepting PetriNet
CaseTrace / EventLog + PetriNet → align_net → minimal deviation witnesses
PetriNet → analyze → qualified reachability/completion/deadlock diagnostics
EventLog → policies, whole-case cohorts, resource handoffs, variant differences
```

| Scenario | Executable and asserted outcomes |
| --- | --- |
| Production/order processing | `moon run --target native examples/model_discovery`: two interleavings reveal a parallel Alpha net, both fit, missing quality costs 1, PNML preserves behaviour |
| Approval/control design | `moon run --target native examples/model_conformance`: XOR BPMN accepts manual or automatic approval, not both; round-trip keeps the deviation cost |
| Ticket/SLA governance | `moon run --target native examples/standard_workflow`: XES preserves core intervals/resources, late self-approval violates SLA and separation of duties; select slow complete cases and count resource handoffs |

These are original synthetic scenarios. They do not assert real enterprise
deployment, causal discovery, or a workflow execution engine.

## Model definitions and execution

`PetriNet::new(places, transitions, arcs, initial, accepting)` creates an ordinary
weighted P/T net. `NetTransition{id, activity:Some(label)}` is observable;
`activity:None` is silent. Multiple transitions may share a visible label.
`NetArc{source,target,weight}` connects one place and one transition. Weights are
1..1,000,000; repeated arcs must be combined explicitly, not silently summed.
Node IDs are globally distinct, nonempty bounded strings. Marking entries name
places once; omitted places have zero tokens; explicit token counts are
0..1,000,000. Net capacity: 4096 places, 8192 transitions, 65536 arcs.

`enabled(marking)` and `fire(marking,transition)` use token subtraction/addition,
including self-arcs and weights. `fire` rejects disabled transitions, wrong
dimensions, negative tokens and overflow, without modifying the input vector.
The final marking is **exact**, not merely a place that has become marked.
No inhibitor/reset/read arcs, colours, priorities, timing or firing side effects.

Input arrays are captured; public getters return copies. `EventLog`, `CaseTrace`,
`ReferencePath` and `AlignmentSpec` now hide mutable arrays. Existing callers
reading fields directly should use `traces()`, `events()`, `activities()`, `id()`,
`paths()` etc. Primitive immutable event values remain readable by their API.

## Discovery is two explicit algorithms, not silent fallback

### Classical Alpha: `log.discover_alpha(max_work?)`

Builds a directly-follows footprint, defines causal `a>b and not b>a`, combines
independent input/output sets, retains maximal pairs as places and adds explicit
initial/final places. Both observed orders of independent branches can produce
concurrent executions rather than two enumerated reference paths.

This is **classical Alpha**, not Alpha+/Alpha++, Inductive Miner or noise-robust
discovery. Observed length-1/length-2 loops are explicitly rejected. At most 16
distinct activities, 4096 candidate places and 65536 tested identities; work budget
default 1,000,000 (maximum 10,000,000) candidate/maximal-pair checks. The algorithm
has exponential candidate growth and completeness/noise/structured-model
assumptions; an incomplete log may yield an unsound or underfitting result.
Always evaluate the discovered net with `analyze` and real conformance samples.
Bidirectional adjacency is an Alpha footprint convention, not causal proof.

### Prefix net: `log.discover_prefix_net(max_nodes?)`

Shares observed prefixes, adds a visible transition for each new activity step
and a silent exit for each accepted prefix. It accepts **exactly the finite
observed label language**; short loops and repeated labels remain explicit
occurrences. It does not infer unseen repetition counts or concurrency. Default
maximum places 4096. Both discovery algorithms reject empty training logs and
return an error on budget exhaustion; neither silently drops infrequent traces.

## Model alignment and behaviour analysis

`trace.align_net(net, limits?)` runs Dijkstra on `(trace index, marking)`:

- synchronous visible moves cost 0;
- log-only and visible model-only moves each cost 1;
- silent model moves cost 0;
- acceptance requires all events consumed and the exact final marking.

Returns `ModelAlignment{case_id,cost,conforming,moves,visited_states,explored_edges,
transition_checks,reused_variant}`. `conforming` means cost zero under the chosen
model, not that the discovered model is correct for all future cases. `moves`
retain original event IDs and model transition IDs. It is not a token-replay
fitness score, normalized PM4Py fitness, or finite-reference-path alignment.

Every returned search is optimal; if state, transition-check, generated-edge,
marking-cell or token caps obstruct exploration it raises `Capacity` rather than
returning a truncated cost. Default `ModelLimits`: 20000 search states, 200000
generated edges **and** transition examinations, 64 tokens/place; maxima 200000,
2000000 and 1000000. State vectors additionally cap at 4,000,000 integer cells.
Counters include dominated offers; states count allocated search records, not a
claim of unique reachable markings. An unreachable accepting marking is an error.

`log.align_net(net,limits?,reuse_variants=true)` aggregates actual search work
over the whole log, charging the maximum of generated edges and transition checks
per searched case against the shared edge limit. Identical activity sequences
reuse one witness and rebind every synchronous/log-only event to the current case.
Reused rows report zero new search work. It does not cache across calls/models,
nor reuse results when resource/time-dependent constraints change; those rules
are evaluated independently. Disable with `reuse_variants=false` to compare.

`net.analyze(limits?)` explores markings and reverse reachability. It reports:

- whether the explicit final marking was found;
- whether every reachable marking can lead to it;
- whether any marking covers all nonzero final tokens plus leftovers;
- non-final deadlock markings and unobserved transitions.

**`complete` is mandatory context.** On state/edge/check/token/cell truncation it
is false; `all_states_can_complete` and `proper_completion` are deliberately false
and unobserved transitions are only candidates, not proven dead. A found final
path remains valid evidence, but a missing path after incomplete exploration is
unknown. Even complete exploration checks an accepting P/T net's behaviour; it
is not a full structural WF-net soundness theorem or unboundedness decision.

## Exchange profiles: no silently ignored execution semantics

### XES

`parse_xes(text,mode=Completed)` accepts the XES log/trace/event XML structure,
namespace absent or `http://www.xes-standard.org/`, scalar attribute types,
`concept:name`, `time:timestamp`, `org:resource` and lifecycle annotations.
Traces require distinct case IDs; event names/time are mandatory after applying
scalar `global scope="trace|event"` defaults. Explicit attributes override defaults;
duplicate scopes are rejected. Empty traces and list/nested attributes are unsupported.
Non-core scalar attributes and log extension/classifier metadata are projected
away; this is not a lossless XES document or alternate-classifier implementation.
Duplicate attributes and core attributes with incorrect XML types are errors.

- `Completed`: lifecycle absent/complete; completion timestamps are points unless
  `lens:started` supplies an explicit interval. IDs use `lens:event_id` if present,
  otherwise deterministic source positions. No hidden default service duration.
- `LifecyclePairs`: requires matched start/complete, keyed by activity and optional
  `concept:instance`. Repeated overlapping occurrences without distinct instance
  IDs are rejected, not paired arbitrarily. Unmatched/reversed intervals, changed
  resources and mixed interval/pairing representations are errors.
- `log.to_xes()` emits completion events, standard activity/time/resource fields,
  plus `lens:started` and `lens:event_id` for interval/identity round-trip.
  Internal timestamps must be Unix **milliseconds**, not arbitrary business ticks.
- Time profile: Gregorian UTC instants in 1970..9999, mandatory `Z`/`±hh:mm`, no
  leap seconds. Up to 9 fraction digits only if exactly representable in whole
  milliseconds; nonzero finer precision is rejected, never rounded. Offsets
  normalize to UTC. Export is canonical three-digit UTC milliseconds.

### PNML

`parse_pnml` / `net.to_pnml()` exchange ordinary weighted P/T nets with one flat
page (or direct nodes), names, initial counts, inscriptions and **one explicit
finalmarkings** element. No accepting sink is guessed. Type URI supports the
P/T transport and PM4Py's `pnmlcoremodel` spelling; that is not permission to
interpret coloured, inhibitor/reset or high-level semantics. Recognizes ProM
`activity="$invisible$"` for silent transitions. Unsupported execution extensions
are rejected; layout/name annotation is ignored where documented.

Exports assign safe canonical XML IDs (`p0`, `t0`, `a0`) and preserve labels, arc
weights and markings. Original internal IDs need not round-trip. This is a
semantic transport, not lossless XML, XSD validation or arbitrary PNML dialects.

### BPMN 2.0 control flow

`parse_bpmn` / `BpmnModel::new` / `to_bpmn` / `to_petri_net` support one process,
one plain start/end, ordinary tasks and XOR/AND split/join gateways. Tasks have
one incoming/outgoing flow; gateways may split or join but not mix both. Parallel
gateways produce/consume all branch tokens; exclusive gateways choose one branch.
Silent transitions encode gateway/start/end steps, not fake activity names.

The importer requires the BPMN model namespace, validates endpoints and redundant
incoming/outgoing references, and rejects conditional flows, execution flags,
default branches, message/timer/boundary events, inclusive gateways, sub/call
processes, collaboration and data/execution extensions. Diagram layout is
nonexecuting metadata. Export normalizes IDs and omits layout. **No complete
BPMN compliance or business-condition execution is claimed.**

### XML transport limits

The original non-validating XML profile accepts Unicode values, ASCII qualified
element/attribute names, scoped namespaces, quotes, comments, CDATA and
predefined/numeric entities. It rejects DTD/custom/external entities and general
processing instructions; no network or filesystem resolution occurs. Limits:
16 Mi UTF-16 input units, depth 48, 200000 nodes, 128 attributes/node. This is not
a general XML library, full Unicode XML-name implementation, XSD validator or a
hard host memory ceiling. Exports materialize output strings; hosts should cap
input and output/log storage further for untrusted data.

## Additional reusable analysis

`check_policies` accepts response, strict precedence, non-coexistence and
separation-of-duties. A response target must occur later in trace order. Timed
response finds a later target starting at/after trigger completion and within
`within_ms`; an overlapping early target cannot hide a valid later one. Same-label
and zero-duration occurrences still require strict occurrence order. Trace order
is the existing stable start/completion/input order, not an inference of causality.

Missing resource values produce **Inconclusive** for otherwise applicable duties;
known counterexamples remain Violated even when other data is missing. Rules with
no applicable trigger/pair report NotApplicable rather than evidence of success.
Event ID evidence is bounded; default at most 256 rules, 10M event-rule checks,
1M result rows, 100000 evidence IDs. The logical work limit bounds event×rule
input, not instruction count (bounded response includes binary searches).

`select_cases(CaseSelection)` selects **whole cases** by required/excluded
activities, cycle range and start-inclusive/end-exclusive start-time window.
It never slices events out of a history or repairs absent events; up to 256
selection activity labels. Duration/time units must match the source log.

`resource_handoffs()` counts adjacent distinct known resources, separating total
occurrences from case coverage; missing actors and same-resource pairs are
omitted. This is an observed network, not causal responsibility or utilization.

`compare_cohort(other)` reports unioned full variants/counts and total-variation
distance of normalized frequencies (0..1). Two nonempty cohorts are required.
It is descriptive drift, not a p-value, bias correction or causal explanation.

## File tools and failure handling

`cmd/processlens` accepts `.xes` or native JSON logs, `.pnml`/`.bpmn`/net JSON models.
Commands: analyze, align (old reference paths), discover/discover-pnml with explicit
alpha/prefix, check, model, to-xes/from-xes completed|pairs, audit, compare, resources.
See README and examples/files. `check` refuses an empty log. Results are fully
prepared before output; inputs/captured logs/models are never partially changed.

Exit codes: 0 success/report, 1 malformed input/unsupported/budget/I/O, 2 command
usage, 3 nonconforming check or violated/inconclusive policy audit. `model` outputs
descriptive analysis; 0 is not a soundness assertion. A process can be conforming
on the observed cases while still having deadlocks on unobserved paths.

`python scripts/verify_model_cli.py` checks **15 executable workflows**, actual
JSON/XML outputs and both negative-input and negative-conformance exit codes.
Core APIs have no I/O; CLI file read currently materializes before checking the
text cap. Use host file-size/process quotas for untrusted files. Reports contain
event/case/resource identities and should be protected or anonymized by hosts.

## PM4Py reference: measured, separated claims

Install `pm4py==2.7.23` into an isolated Python 3.11 environment (or ignored
`.local/pm4py-runtime`), then run `python scripts/compare_pm4py.py`. The runner
builds and invokes MoonBit, exchanges original synthetic fixtures, and asserts:

| Independently exercised path | Passing observations |
| --- | --- |
| PM4Py Dijkstra vs model alignment, all words length 0..4 over A/B/X, four nets (sequence, XOR, AND, loop) | 484/484 minimal unit-cost results |
| PM4Py weighted firing → enumerate finite accepted language → independent edit distance vs weighted model | 121/121 costs |
| PM4Py classical Alpha discovery on both parallel interleavings vs our discovered behaviour | 6/6 costs |
| MoonBit XES → PM4Py reader | 8/8 activity events in 2 traces |
| MoonBit PNML → PM4Py reader/conformance | 2/2 traces |
| MoonBit BPMN → PM4Py importer/converter/conformance | 3/3 traces |
| PM4Py writes XES/PNML → MoonBit CLI imports and checks | 2/2 traces |

Costs explicitly use visible model/log=1, sync/silent=0, not PM4Py's default
10000/1 scale or normalized fitness. Do not compare trace witnesses bit-for-bit:
multiple equally optimal alignments may exist. A reference-path exhaustive
121-word test separately checks the finite-language parallel case in MoonBit.

The PM4Py alignment synchronous-product path returned no alignment on the weighted
fixture; it is **not** counted as a passing direct alignment comparison. The
separate weighted language test uses its ordinary weighted firing and an acyclic
fixture whose sole accepted word is AAB. No claim about all weighted nets or a
general PM4Py defect follows. The fixed positive/negative fixture counts above
are not full standards conformance or PM4Py feature parity.

PM4Py is AGPL-3.0, used only as an optional external development oracle; no source
was copied/translated into the MIT core. The capability catalogue of PM4Py is much
larger (including robust discovery, full ecosystems and advanced diagnostics).
See [source and license notes](sources.md) for honest ecosystem positioning,
including the existing adjacent MoonBit Petri simulator.

## Algorithms, performance and residual limits

Let L be total log events, A distinct activities, C Alpha candidates, P places,
T transitions, S allocated search records, G generated search edges and K total
transition examinations, V observed variants. Hash maps use expected costs.

- Alpha: DFG/grouping/sorting followed by exponential candidate closure;
  tested pair merging checks activity independence/causality, roughly
  O(C²·A²), plus candidate/maximal identity work. Explicit caps are essential.
  Not suitable for unconstrained hundreds-of-activity noisy logs.
- Prefix net: expected O(L) key construction/trie operations excluding label
  lengths and terminal sorting, O(prefix count) model space. Observed language
  exactness trades away generalisation.
- Net alignment: Dijkstra with binary heap and marking vectors; roughly
  O(K·max input-degree + G·P + G log S), space O(S·P+G), plus key strings and
  witness arrays. Worst reachable product may grow as `(trace_len+1)(cap+1)^P`;
  bounds do not make arbitrary Petri-net alignment polynomial.
- Reachability: analogous vector/transition work without the trace product;
  reverse-edge completion scan O(S+G), storage O(S·P+G). Incomplete remains unknown.
- Batch caching: unique variants pay search once, every case pays trace-key and
  witness rebinding cost; retains cached and per-case witness arrays. It helps
  repeated variants, not diverse traces or model changes, and is call-local.
- Policies mostly O(rule×L); timed response uses O(rule×L log max_trace).
  Cohort selection is O(L×selection labels) in the straightforward implementation;
  resource network expected O(L), cohort difference adds variant-key sorting.
- XML transport is O(input size) with bounded token matching and a depth-bounded
  tree; attribute/namespace maps have copying costs. Date parsing uses bounded
  Gregorian arithmetic, export binary-searches year and scans at most 12 months.

Measured locally 2026-10-23, Windows 10 x64, Intel64 Family 6 Model 165,
moonc v0.10.16+b1a0e846e, native release. `examples/model_scale` compares **2000
cases/4000 events/4 variants**, 10 rounds, including equality of each cost, case ID
and complete event witness. Per round: 1996 reused cases, 32 cached search records
versus 16000 uncached; latest P50/P95 **3/5ms vs 52/65ms** (an earlier run was
4/4ms vs 52/62ms). The 20000 row comparisons are
not independent standard conformance cases. Millisecond timer granularity, order,
allocation and workload matter; no universal speedup/RSS claim. Existing 60000
event performance workloads remain separate and do not prove model search scale.

For untrusted models/logs, add host CPU/heap/output quotas; even bounded state
vectors do not cap every allocation, and retaining many snapshots/results costs
memory. No network fetch, thread-safe execution scheduler, hard realtime guarantee,
OCEL, work-calendar interpretation, or arbitrary BPMN execution is provided.
