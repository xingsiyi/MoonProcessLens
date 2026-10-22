# MoonCEP

MoonCEP is an embeddable **complex event pattern detector** written in MoonBit.
It recognizes named sequences in keyed, out-of-order business events and waits
for caller-provided watermarks before confirming time-bounded absence.

MoonCEP 面向需要跨多条事件识别业务过程的开发者：账号异常登录、订单超时未支付、
设备告警与恢复、用户行为漏斗。核心输入是已经发生的事件，输出是命名捕获及事件证据。
它不运行外部业务动作，也不要求部署流计算集群。

## Local development

The working module is `local/mooncep` and is marked private for local verification.
The release namespace and repository will be supplied by the project owner.
`local` is a temporary development prefix, not a publisher account.

Packages inside this module import the library using:

```moonbit
import {
  "local/mooncep" @cep,
}
```

The library imports only `moonbitlang/core`. The module additionally depends on
`moonbitlang/x@0.4.49` for the file CLI. Tested with moonc 0.10.16 on wasm,
wasm-gc, JavaScript and native; CI checks and builds all four targets.

## Recognize a sequence

```moonbit
fn main raise {
  let pattern = @cep.Pattern::new("login-signal", [
    @cep.Stage::new("failures", @cep.Kind("failed"), min=3, max=3),
    @cep.Stage::new("success", @cep.Kind("success")),
  ], 300000L, after_match=@cep.SkipPastLast)
  let engine = @cep.Engine::new([pattern])
  for (id, kind, time) in [
    ("f1", "failed", 1000L), ("f2", "failed", 2000L),
    ("f3", "failed", 3000L), ("s1", "success", 4000L),
  ] {
    ignore(engine.push(@cep.Event::new(id, "user/7", time, kind)))
  }
  let batch = engine.advance_watermark(4000L)
  assert_eq(batch.matches().length(), 1)
  println(@cep.match_to_json(batch.matches()[0]).stringify())
}
```

All timestamps use caller-chosen consistent integer units. Examples use
milliseconds. A watermark `W` closes **all event times <= W**. Events at the
same timestamp follow successful input occurrence order; an event at an already
closed timestamp is rejected. `finish()` closes every supported deadline.

## Capabilities and boundaries

- Named stages, finite `min..max` repetitions, optional stages (`min=0`).
- Strict, skip-next and skip-any contiguity; three explicit after-match policies.
- Typed field predicates, Boolean combinations and earlier-capture comparisons.
- Stage exclusion predicates and trailing absence through a closed deadline.
- Key isolation, event-time heap, deterministic capture evidence and timeouts.
- Atomic limits on buffered events, states, keys, selected outputs and work units.
- Detached checkpoints, versioned JSON session journals, bounded replay and preview.
- Incremental NDJSON framing, transactional stream ingestion, typed alert projections,
  partial-match diagnostics and bounded detection telemetry.

Version 1 has finite patterns and synchronous, single-owner state. It does not
provide distributed execution, unbounded repetition, pattern alternation/groups,
greedy matching, event corrections/retractions, cross-key joins, arbitrary user
callbacks, automatic watermarks, queue connectors or external-sink exactly-once
delivery. It defines its own semantics and does not claim FlinkCEP compatibility.
See [semantics](docs/semantics.md), [API guide](docs/api.md) and
[resource/complexity model](docs/performance.md).

## Run complete examples

From a source checkout, run `moon update`, then:

```sh
moon run --target native examples/security
moon run --target native examples/orders
moon run --target native examples/equipment
moon run --target native examples/funnel
moon run --target native --release examples/performance
```

| Example | Complete input-to-output scenario |
| --- | --- |
| Security | Three failed logins followed by success for the same account produce captured evidence. |
| Orders | A persisted session is restored; unpaid orders are confirmed after their deadline, while payment at the deadline cancels absence. |
| Equipment | Out-of-order alarms, a rising field comparison and recovery produce a typed operational record. |
| Funnel | An optional coupon stage and multiple purchases demonstrate preview, branching and result telemetry. |

The synthetic fixtures were created for this repository; no production data is included.

## File CLI

```sh
moon run --target native cmd/mooncep -- validate examples/files/program.json
moon run --target native cmd/mooncep -- run examples/files/program.json examples/files/events.ndjson
moon run --target native cmd/mooncep -- inspect SESSION.json
moon run --target native cmd/mooncep -- restore SESSION.json EVENTS.ndjson
```

`run` emits JSON batches, configured alert records and final counters. `restore`
emits batches from new commands and finalization; it does not replay old results
to a sink. The CLI loads each file into memory and bounds it to 16 Mi UTF-16 units;
library text documents and individual NDJSON lines have smaller bounds.
See [wire formats](docs/formats.md).

On the affected Windows 0.10.16 toolchain, replace `moon ...` with
`& .\scripts\Invoke-Moon.ps1 ...`. The wrapper adapts extended drive paths for the
installed official compiler and formatter and restores process environment settings.
It does not change the installed tools. Other toolchain versions use normal commands.

## Verify

```sh
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon fmt --check
moon info
git diff --exit-code
python scripts/verify_repository.py
```

Tests include independent exhaustive subsequence enumeration, optional/repeated
stages, skip policies, window equality, negative predicates, late data, rollback,
exact Int64 values, Unicode chunk boundaries and session ownership.

MIT licensed. This is an independent implementation with AI assistance, not a
source-code port of Apache Flink. Conceptual references and dependency licensing
are documented in [sources](docs/sources.md). See [contributing](CONTRIBUTING.md)
for maintenance expectations and [CHANGELOG](CHANGELOG.md) for release scope.
