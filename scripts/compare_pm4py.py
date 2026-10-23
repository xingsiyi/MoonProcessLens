"""Run independent PM4Py 2.7.23 comparisons on original synthetic fixtures.

Optional oracle, not runtime dependency. Install PM4Py in a venv or the ignored
.local/pm4py-runtime. Source implementation is not copied or translated.
"""
from pathlib import Path
import importlib.metadata
import json
import os
import subprocess
import sys
import tempfile

from native_artifact import processlens_executable

ROOT = Path(__file__).resolve().parents[1]
isolated = ROOT / ".local" / "pm4py-runtime"
if isolated.exists():
    sys.path.insert(0, str(isolated))
import pm4py
from pm4py.objects.log.obj import EventLog, Trace, Event
from pm4py.objects.petri_net.obj import PetriNet, Marking
from pm4py.objects.petri_net.utils.petri_utils import add_arc_from_to
from pm4py.objects.petri_net import semantics
from pm4py.algo.conformance.alignments.petri_net import algorithm as align
from pm4py.algo.discovery.alpha import algorithm as alpha


def typed_net(row):
    net = PetriNet("original-fixture")
    places = {name: PetriNet.Place(name) for name in row["places"]}
    transitions = {t["id"]: PetriNet.Transition(t["id"], t["activity"])
                   for t in row["transitions"]}
    net.places.update(places.values())
    net.transitions.update(transitions.values())
    nodes = {**places, **transitions}
    for arc in row["arcs"]:
        add_arc_from_to(nodes[arc["source"]], nodes[arc["target"]], net, weight=arc["weight"])
    initial = Marking({places[p]: n for p, n in zip(row["places"], row["initial"]) if n})
    final = Marking({places[p]: n for p, n in zip(row["places"], row["final"]) if n})
    return net, initial, final


def pm_trace(labels):
    return Trace([Event({"concept:name": name}) for name in labels])


def cost(net, initial, final, labels):
    trace = pm_trace(labels)
    params = {"model_cost_function": {t: 0 if t.label is None else 1 for t in net.transitions},
              "sync_cost_function": {t: 0 for t in net.transitions},
              "trace_cost_function": [1] * len(trace)}
    result = align.apply_trace(trace, net, initial, final, parameters=params,
                               variant=align.Variants.VERSION_DIJKSTRA_NO_HEURISTICS)
    if result is None:
        raise AssertionError(f"reference did not return a complete alignment: {[t.label for t in net.transitions]}, trace={labels}")
    return result["cost"]


def check_observations(model, observations):
    for row in observations:
        actual = cost(*model, row["trace"])
        if actual != row["cost"]:
            raise AssertionError(f"alignment mismatch: {row['trace']} expected {row['cost']}, PM4Py {actual}")
    return len(observations)


def weighted_observations(model, observations):
    # PM4Py 2.7.23's alignment synchronous product does not preserve this
    # weighted fixture. Do not quietly count missing alignments as matches.
    # Independently enumerate its finite language using PM4Py weighted firing,
    # then compute unit insertion/deletion distance against that language.
    net, initial, final = model
    stack = [(initial, [])]
    language = []
    while stack:
        marking, path = stack.pop()
        if marking == final:
            language.append(path)
        if len(path) >= 8:
            raise AssertionError("weighted reference fixture must be acyclic and finite")
        for transition in semantics.enabled_transitions(net, marking):
            next_path = path + ([transition.label] if transition.label is not None else [])
            stack.append((semantics.execute(transition, net, marking), next_path))
    assert language == [["A", "A", "B"]], language
    for row in observations:
        values = []
        for accepted in language:
            previous = list(range(len(accepted) + 1))
            for i, actual in enumerate(row["trace"], 1):
                current = [i]
                for j, expected in enumerate(accepted, 1):
                    current.append(min(previous[j] + 1, current[j - 1] + 1,
                                       previous[j - 1] + (0 if actual == expected else 2)))
                previous = current
            values.append(previous[-1])
        assert min(values) == row["cost"], row
    return len(observations)


def main():
    (ROOT / ".local").mkdir(exist_ok=True)
    if importlib.metadata.version("pm4py") != "2.7.23":
        raise AssertionError("reference must be pinned to pm4py==2.7.23")
    launcher = (["pwsh", "-NoProfile", "-File", str(ROOT / "scripts/Invoke-Moon.ps1")]
                if os.name == "nt" else ["moon"])
    output = subprocess.run(launcher + ["run", "scripts/model_reference", "--target", "wasm-gc", "--frozen"],
                            cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=True)
    if output.stderr:
        print(output.stderr, file=sys.stderr, end="")
    counts = {"model_alignment_costs": 0, "weighted_language_costs": 0, "alpha_discovery_costs": 0,
              "xes_events": 0, "pnml_import_costs": 0, "bpmn_conversion_costs": 0, "reverse_interchange_cases": 0}
    subprocess.run(launcher + ["build", "cmd/processlens", "--target", "native", "--frozen"], cwd=ROOT, check=True)
    cli = processlens_executable(ROOT)
    for line in output.stdout.splitlines():
        row = json.loads(line)
        if row["kind"] == "alignment":
            print(f"Comparing {row['name']}", file=sys.stderr)
            counts["model_alignment_costs"] += check_observations(typed_net(row["net"]), row["observations"])
        elif row["kind"] == "weighted":
            counts["weighted_language_costs"] += weighted_observations(typed_net(row["net"]), row["observations"])
        elif row["kind"] == "alpha":
            train = EventLog([pm_trace(labels) for labels in row["training"]])
            model = alpha.apply(train)
            counts["alpha_discovery_costs"] += check_observations(model, row["observations"])
        elif row["kind"] == "interchange":
            with tempfile.TemporaryDirectory(prefix="lens-interop-", dir=ROOT / ".local") as temp:
                folder = Path(temp)
                for extension in ("xes", "pnml", "bpmn"):
                    (folder / f"fixture.{extension}").write_text(row[extension], encoding="utf-8")
                log = pm4py.read_xes(str(folder / "fixture.xes"), return_legacy_log_object=True)
                assert [list(e["concept:name"] for e in t) for t in log] == [["A", "B", "C", "D"], ["A", "C", "B", "D"]]
                counts["xes_events"] += sum(len(t) for t in log)
                model = pm4py.read_pnml(str(folder / "fixture.pnml"))
                expected = [{"trace": [e["concept:name"] for e in t], "cost": 0} for t in log]
                counts["pnml_import_costs"] += check_observations(model, expected)
                # Reverse direction: the mature tool writes new XML files; the
                # MoonBit CLI parses them and aligns the reconstructed cases.
                pm4py.write_xes(log, str(folder / "reference.xes"))
                pm4py.write_pnml(*model, str(folder / "reference.pnml"))
                reverse = subprocess.run([str(cli), "check", str(folder / "reference.xes"), str(folder / "reference.pnml")],
                                         cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
                if reverse.returncode:
                    raise AssertionError(f"reverse XML failed: {reverse.stdout} {reverse.stderr}")
                back = json.loads(reverse.stdout)
                assert len(back["alignments"]) == 2 and all(r["cost"] == 0 for r in back["alignments"])
                counts["reverse_interchange_cases"] += len(back["alignments"])
                bpmn = pm4py.read_bpmn(str(folder / "fixture.bpmn"))
                model = pm4py.convert_to_petri_net(bpmn)
                counts["bpmn_conversion_costs"] += check_observations(model, row["bpmn_expected"])
    assert counts == {"model_alignment_costs": 484, "weighted_language_costs": 121, "alpha_discovery_costs": 6,
                      "xes_events": 8, "pnml_import_costs": 2, "bpmn_conversion_costs": 3, "reverse_interchange_cases": 2}, counts
    print(json.dumps({"reference": "PM4Py", "version": "2.7.23", "matched": counts}, ensure_ascii=False))


if __name__ == "__main__":
    main()
