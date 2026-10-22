# Contributing

Use MoonBit's standard formatter and generated interfaces. Keep public contracts
in docs/semantics.md and root CONTEXT.md consistent with behavior. Record only
substantial architectural trade-offs in docs/adr/.

Changes to ordering, selection, expiry or ownership need regression tests against
the affected public interface. Extend the independent exhaustive oracle when a
new sequence construct can be modeled independently. Keep synthetic fixtures
small and document the source/license of any imported fixture.

Run check/build/test for all four targets with --deny-warn, moon fmt --check,
moon info, the runnable examples and scripts/verify_repository.py. CI uses the
current official stable installer; the release was developed with moonc 0.10.16.
When the language changes, update implementation and tests together.

Use GitHub Issues for bug reports and specifications. Default triage labels are
needs-triage, needs-info, ready-for-agent, ready-for-human and wontfix. Include a
minimal event sequence, pattern, watermarks, expected captures and toolchain
version. Never upload private production events to illustrate a bug.

Competition proposals, reviews, AI process reports and private measurement logs
belong outside the project checkout and must not be staged. Preserve existing
source files before significant edits when working under the parent workspace's
instructions. Keep commits focused on real features, fixes or useful validation.
