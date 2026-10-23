"""Exercise executable file workflows, parse outputs and verify failure exits."""
from pathlib import Path
import json
import os
import subprocess
import tempfile

from native_artifact import processlens_executable

ROOT = Path(__file__).resolve().parents[1]


def main():
    (ROOT / ".local").mkdir(exist_ok=True)
    launcher = (["pwsh", "-NoProfile", "-File", str(ROOT / "scripts/Invoke-Moon.ps1")]
                if os.name == "nt" else ["moon"])
    subprocess.run(launcher + ["build", "cmd/processlens", "--target", "native", "--frozen"], cwd=ROOT, check=True)
    cli = processlens_executable(ROOT)
    count = 0

    def run(*args, expected=0):
        nonlocal count
        result = subprocess.run([str(cli), *map(str, args)], cwd=ROOT,
                                capture_output=True, text=True, encoding="utf-8")
        if result.returncode != expected:
            raise AssertionError(f"{args}: exit {result.returncode}, expected {expected}: {result.stdout} {result.stderr}")
        count += 1
        return result.stdout

    log = ROOT / "examples/files/model-log.xes"
    bpmn = ROOT / "examples/files/parallel.bpmn"
    checked = json.loads(run("check", log, bpmn))
    assert all(row["conforming"] for row in checked["alignments"])
    assert checked["model"]["complete"]
    assert json.loads(run("model", bpmn))["all_states_can_complete"]
    assert len(json.loads(run("from-xes", log, "completed"))["events"]) == 4
    assert len(json.loads(run("discover", log, "prefix"))["transitions"]) > 0
    assert json.loads(run("compare", log, log))["total_variation"] == 0
    assert json.loads(run("resources", log)) == []
    audit = json.loads(run("audit", log, ROOT / "examples/files/policies.json", expected=3))
    assert any(row["status"] == "violated" for row in audit)
    with tempfile.TemporaryDirectory(prefix="lens-cli-", dir=ROOT / ".local") as temp:
        folder = Path(temp)
        pnml = folder / "model.pnml"
        pnml.write_text(run("discover-pnml", log, "prefix"), encoding="utf-8")
        assert all(row["conforming"] for row in json.loads(run("check", log, pnml))["alignments"])
        exported = folder / "export.xes"
        exported.write_text(run("to-xes", log), encoding="utf-8")
        assert len(json.loads(run("from-xes", exported, "completed"))["events"]) == 4
        bad = folder / "bad.xes"
        bad.write_text("<!DOCTYPE log SYSTEM 'file:///forbidden'><log/>", encoding="utf-8")
        assert "ERROR" in run("from-xes", bad, "completed", expected=1)
        bad.write_text("<log><trace><string key='concept:name' value='bad'/><event><string key='concept:name' value='X'/><date key='time:timestamp' value='1970-01-01T00:00:00Z'/></event></trace></log>", encoding="utf-8")
        assert not json.loads(run("check", bad, bpmn, expected=3))["alignments"][0]["conforming"]
        run("from-xes", log, "invalid-mode", expected=1)
        run("unknown", log, expected=2)
    assert count == 15, count
    print(json.dumps({"cli_workflows": count, "outputs_and_exit_codes_verified": True}))


if __name__ == "__main__":
    main()
