"""Verify source scale and tracked-file hygiene using only the Python stdlib."""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GIT = ["git", "-c", f"safe.directory={ROOT.as_posix()}", "-C", str(ROOT)]


def git(*args):
    return subprocess.check_output(GIT + list(args), text=True, encoding="utf-8").strip()


def code_lines(path):
    # Conventional effective source count: nonblank, noncomment physical lines.
    # Generated .mbti interfaces and all test/example/CLI files are separate.
    return sum(bool(line.strip()) and not line.lstrip().startswith("//")
               for line in path.read_text(encoding="utf-8-sig").splitlines())


def inspect():
    tracked = git("ls-files", "-z").split("\0")
    forbidden = re.compile(
        r"申报|审查报告|验收报告|辅助报告|汇总报告|调研报告|研究报告|"
        r"ai[-_]?report|review[-_]?report|acceptance[-_]?report|proposal|"
        r"(^|/)(_build|target|\.mooncakes|\.local|\.build-check|__pycache__)(/|$)", re.I)
    leaked = [name for name in tracked if name and forbidden.search(name)]
    if leaked:
        raise ValueError("tracked local material/build output: " + ", ".join(leaked))
    production = tests = examples = cli = 0
    production_by_package = {}
    for name in tracked:
        if not name.endswith(".mbt"):
            continue
        count = code_lines(ROOT / name)
        if name.endswith(("_test.mbt", "_wbtest.mbt")):
            tests += count
        elif name.startswith("examples/"):
            examples += count
        elif name.startswith("cmd/"):
            cli += count
        else:
            production += count
            package = str(Path(name).parent).replace("\\", "/")
            production_by_package[package] = production_by_package.get(package, 0) + count
    commits = int(git("rev-list", "--count", "HEAD"))
    if production <= 4000:
        raise ValueError(f"production MoonBit code must exceed 4000 lines; got {production}")
    if commits <= 30:
        raise ValueError(f"history must exceed 30 commits; got {commits}")
    empty = []
    for commit in git("rev-list", "HEAD").splitlines():
        paths = git("diff-tree", "--no-commit-id", "--name-only", "--root", "-r", commit)
        if not paths:
            empty.append(commit)
    if empty:
        raise ValueError("empty development commits: " + ", ".join(empty))
    history_paths = git("log", "--all", "--format=", "--name-only").splitlines()
    historical_leaks = sorted({name for name in history_paths if forbidden.search(name)})
    if historical_leaks:
        raise ValueError("local material/build output remains in Git history: " + ", ".join(historical_leaks))
    return {"production_moonbit_lines": production,
            "production_by_package": production_by_package, "test_lines": tests,
            "example_lines": examples, "cli_lines": cli,
            "commits": commits, "tracked_local_materials": leaked,
            "count_definition": "nonblank, noncomment physical .mbt lines; excludes generated interfaces"}


if __name__ == "__main__":
    try:
        print(json.dumps(inspect(), ensure_ascii=False, indent=2))
    except (ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
