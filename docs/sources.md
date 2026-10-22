# Sources, ecosystem position and licensing

MoonProcessLens has an independent process-log root package: case reconstruction,
empirical directly-follows discovery, finite-reference weighted edit alignment and
interval performance analysis. Its code and synthetic fixtures were created with AI
assistance; no external process-mining source or production dataset was imported.
The alignment is a direct dynamic program verified against independently enumerated
common subsequences, not a port of a Petri-net alignment engine.

A 2026-10-22 review of 3,221 official directory entries and selected fixed APIs did
not identify an equivalent complete process-analysis library within that scope.
[moonpetri](https://github.com/okMambaOut/moonpetri/tree/e5eb4ed854be19e68dcb4ddb092f8d0bf6be61f5)
models/fires Petri nets; [moonflowgraph](https://github.com/AlexenderSokolov/moonflowgraph/tree/e2faa7c7105161b561111f0f31e1ef57071b713d)
plans predefined task DAGs. [moon-loglens](https://github.com/sundaysebasidian-byte/moon-loglens/tree/4603ef7527332002684200ff4a9a88c313f944f4)
provides general JSONL aggregation, while [moon-tracelens](https://github.com/btlqql/moon-tracelens)
provides ingestion, timeline and metric comparisons. ProcessLens instead groups
activity histories into case paths and produces path edits and interval explanations.
These bounded findings do not establish that all concepts or primitives are new.

## Evolution and optional sequence package

The project continues the local repository previously named MoonCEP. Its detector
is now in `sequence`; it is retained and identified rather than presented as new
process-mining code. Root analysis does not import it. Renaming does not erase Git
history or previously published artifacts. Package/account changes require the owner's
later instructions. The original detector's source/reference notes follow.


MoonCEP's MoonBit implementation and synthetic tests were created for this
project with AI assistance. It is not a line-by-line port and does not include
Apache Flink or SASE source code, diagrams or external data fixtures.

Conceptual references:

- [Apache Flink CEP documentation](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/libs/cep/): vocabulary for contiguity, repetition and match selection. Flink is Apache-2.0 licensed; MoonCEP defines independent boundary behavior.
- [Wu, Diao and Rizvi, SASE, SIGMOD 2006](https://www.cs.columbia.edu/~ewu/files/papers/sase-sigmod06.pdf): automata-based event recognition, windows and delayed absence confirmation.
- [Agrawal et al., SIGMOD 2008](https://people.cs.umass.edu/~yanlei/publications/sase-sigmod08.pdf): take/ignore/proceed choices and capture evidence for event-stream matching.
- [Foundations of Complex Event Processing](https://arxiv.org/abs/1709.05369): explicit semantics and the importance of stating the supported model before claiming complexity guarantees.

Dependencies: the standard library is supplied by the MoonBit toolchain.
The file CLI uses [moonbitlang/x](https://github.com/moonbitlang/x) 0.4.49 under
Apache-2.0. Dependency source is fetched by Moon, not vendored or relicensed.
The original project code is MIT licensed, as stated in the root LICENSE.

The small C#/PowerShell Windows argument adapter is reused from the author's
local MoonBit tooling and adapted to this project. It changes only extended
drive-path arguments passed to installed official tools. It is auxiliary build
code and excluded from the MoonBit source-size count.

## Ecosystem position

MoonCEP's independent contribution is temporal sequence recognition with named
captures, repetition, exclusion/absence and explicit selection semantics.
[Moon Stream Quality](https://github.com/zmjknn/moon-stream-quality) evaluates
data-quality rules; [TideWeave](https://github.com/LMK-ai-nb/TideWeave) maintains
correctable aggregate windows; [MoonUp](https://github.com/mw1696803-hub/moonup)
implements Rete working-memory rules. Their event and time primitives are adjacent
capabilities; this project does not claim those primitives are new to MoonBit.

Directory and source checks on 2026-10-22 did not identify an equivalent published
sequence detector. This is a dated, scoped investigation, not proof that no hidden
or subsequently released implementation exists. Detailed process reports and
competition materials are maintained outside this repository.
