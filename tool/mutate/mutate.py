#!/usr/bin/env python3
"""Operator-flip mutants of app code, each run against chosen Flutter test files.

A mutant flips one operator (== and !=, && and ||, isEmpty and isNotEmpty, any and every, true and
false, ...) on one line. A test set that still passes with it lets that line's logic change
unnoticed: the mutant SURVIVED. One that fails, fails to compile or hangs (TIMEOUT) killed it.

  tool/mutate/mutate.py run <spec.tsv> [--workers N] [--done <earlier output>]
      Spec rows: <file under app/> TAB <first line regex> TAB <last line regex> TAB <test files>.
      The range runs from the first line matching the first regex to the next one matching the
      last (an empty one: the end of the file). Each worker mutates its own copy of app/ under
      /tmp, beside links to the rest of the repo (tests read ../supabase and others); the tests
      first run unmutated in such a copy and must pass. Prints one row per mutant as it ends:
      status, file, line, column, old, new, source line. --done skips the mutants an earlier
      output lists, by file, line and column: edit nothing in the ranges between the two runs.

  tool/mutate/mutate.py prove <rows.tsv> [--workers N] <test files...>
      Runs each row (as `run` prints them) against the test files, in the same copies. Use it to
      show that new tests kill the mutants that survived.

Flutter is FLUTTER_DIR's, else ~/flutter-<CI's FLUTTER_VERSION> when it exists, else the one on
PATH, as scripts/lib.sh picks it. A mutant that runs longer than MUTATE_TIMEOUT seconds (default 300) is TIMEOUT: a hang, or a test
set too slow for the limit. tool/mutate/hotpaths.tsv is the spec of job 448 (docs/done/448.md).
"""
import concurrent.futures
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
APP = REPO / "app"
TIMEOUT = int(os.environ.get("MUTATE_TIMEOUT", "300"))
OPS = [
    (" == ", " != "), (" != ", " == "), (" && ", " || "), (" || ", " && "),
    (" < ", " <= "), (" <= ", " < "), (" > ", " >= "), (" >= ", " > "),
    (".isEmpty", ".isNotEmpty"), (".isNotEmpty", ".isEmpty"),
    ("true", "false"), ("false", "true"), ("(!", "("), (" !", " "),
    (".isAfter(", ".isBefore("), (".isBefore(", ".isAfter("),
    (" + 1", " - 1"), (" - 1", " + 1"), ("?? false", "?? true"), ("?? true", "?? false"),
    (".any(", ".every("), (".every(", ".any("),
]


def flutter_bin() -> Path | None:
    if dir := os.environ.get("FLUTTER_DIR"):
        return Path(dir) / "bin"
    ci = (REPO / ".github/workflows/ci.yml").read_text()
    if pin := re.search(r"^ *FLUTTER_VERSION: *(\S+)", ci, re.M):
        beside = Path.home() / f"flutter-{pin[1]}" / "bin"
        if beside.is_dir():
            return beside
    return None


ENV = dict(os.environ)
if (sdk := flutter_bin()) is not None:
    ENV["PATH"] = f"{sdk}{os.pathsep}{ENV['PATH']}"


def mutants(rel: str, first: str, last: str):
    lines = (APP / rel).read_text().split("\n")
    start = next((i for i, line in enumerate(lines) if re.search(first, line)), None)
    if start is None:
        sys.exit(f"{rel}: no line matches {first!r}")
    end = next((i for i in range(start, len(lines)) if last and re.search(last, lines[i])),
               len(lines) - 1)
    for n in range(start + 1, end + 2):
        src = lines[n - 1]
        if src.lstrip().startswith(("//", "import ")):
            continue
        for old, new in OPS:
            for m in re.finditer(re.escape(old), src):
                word = old in ("true", "false")
                if word and re.match(r"\w", src[m.end():m.end() + 1] or " "):
                    continue
                if word and m.start() and re.match(r"\w", src[m.start() - 1]):
                    continue
                if old == " !" and src[m.end():m.end() + 1] in ("=", " "):
                    continue
                yield rel, n, m.start(), old, new, src


def flutter_test(app: Path, tests: list[str]) -> str:
    proc = subprocess.Popen(
        ["flutter", "test", "--no-pub", "--reporter=compact", *tests],
        cwd=app, env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    try:
        return "SURVIVED" if proc.wait(timeout=TIMEOUT) == 0 else "killed"
    except subprocess.TimeoutExpired:
        # The whole group: flutter_tester outlives its flutter parent.
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        return "TIMEOUT"


def mutated(app: Path, rel: str, n: int, col: int, old: str, new: str):
    path = app / rel
    orig = path.read_text()
    lines = orig.split("\n")
    src = lines[n - 1]
    at = src.index(old.strip(), col)
    lines[n - 1] = src[:at] + new.strip() + src[at + len(old.strip()):]
    path.write_text("\n".join(lines))
    return path, orig


def baseline(app: Path, tests: list[str]) -> None:
    """Stops unless the tests pass unmutated: else every mutant would read as killed."""
    if flutter_test(app, tests) != "SURVIVED":
        sys.exit(f"the tests fail without a mutant in {app}: {' '.join(tests)}")


def row(status, rel, n, col, old, new, src) -> str:
    return "\t".join([status, rel, str(n), str(col), old.strip(), new.strip(), src.strip()])


def parse_rows(path: str):
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 7 and not line.startswith("#"):
            yield f[1], int(f[2]), int(f[3]), f[4], f[5], f[6]


def in_slots(jobs, workers: int) -> None:
    """Runs (mutant, tests) jobs in parallel copies of app/ and prints a row as each ends."""
    free = []
    for i in range(workers):
        root = Path(f"/tmp/mutate-{os.getpid()}/slot{i}")
        root.mkdir(parents=True)
        for entry in REPO.iterdir():
            if entry.name != "app":
                (root / entry.name).symlink_to(entry)
        shutil.copytree(APP, root / "app", symlinks=True,
                        ignore=shutil.ignore_patterns("build", "coverage"))
        free.append(root / "app")
    try:
        for tests in {tuple(t) for _, t in jobs}:
            baseline(free[0], list(tests))
        print(f"# {len(jobs)} mutants", file=sys.stderr, flush=True)
        lock = threading.Lock()

        def work(job):
            (rel, n, col, old, new, src), tests = job
            with lock:
                slot = free.pop()
            try:
                path, orig = mutated(slot, rel, n, col, old, new)
                try:
                    return row(flutter_test(slot, tests), rel, n, col, old, new, src)
                finally:
                    path.write_text(orig)
            finally:
                with lock:
                    free.append(slot)

        with concurrent.futures.ThreadPoolExecutor(workers) as pool:
            for result in concurrent.futures.as_completed([pool.submit(work, j) for j in jobs]):
                print(result.result(), flush=True)
    finally:
        shutil.rmtree(f"/tmp/mutate-{os.getpid()}")


def run(spec: str, workers: int, done_file: str | None) -> None:
    done = {m[:4] for m in parse_rows(done_file)} if done_file else set()
    jobs = []
    for line in open(spec):
        if line.strip() and not line.startswith("#"):
            rel, first, last, tests = line.rstrip("\n").split("\t")
            for m in mutants(rel, first, last):
                if (m[0], m[1], m[2], m[3].strip()) not in done:
                    jobs.append((m, tests.split()))
    in_slots(jobs, workers)


def prove(rows: str, tests: list[str], workers: int) -> None:
    in_slots([(m, tests) for m in parse_rows(rows)], workers)


def main() -> None:
    args = sys.argv[1:]
    workers = 3
    if "--workers" in args:
        at = args.index("--workers")
        workers = int(args[at + 1])
        del args[at:at + 2]
    if args[:1] == ["run"] and len(args) >= 2:
        done = args[args.index("--done") + 1] if "--done" in args else None
        run(args[1], workers, done)
    elif args[:1] == ["prove"] and len(args) >= 3:
        prove(args[1], args[2:], workers)
    else:
        sys.exit(__doc__)


main()
