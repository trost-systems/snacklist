#!/usr/bin/env python3
"""Launches the ui_perf_probe build once to warm the caches (discarded) and
then <runs> times, each against a fresh fake_supabase.py (the flows change
its rows), and prints one JSON line: every run's per-flow frame stats and
score. Each launch gets a fresh data directory holding only a signed-in
session; the cache directory (Mesa's shader cache, fontconfig's) is shared
and filled by the warm-up. Run it inside an X server (xvfb-run).

    frames.py <bundle dir> <port> <runs> <scenarios dir>
"""

import base64
import json
import math
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
USER = "00000000-0000-4000-8000-000000000001"
BUDGET_MS = 16.7


def b64(obj):
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def session():
    token = ".".join(
        [
            b64({"alg": "HS256", "typ": "JWT"}),
            b64({"sub": USER, "role": "authenticated", "aud": "authenticated", "exp": 4102444800}),
            "c2ln",
        ]
    )
    return json.dumps(
        {
            "access_token": token,
            "token_type": "bearer",
            "expires_in": 3600,
            "expires_at": 4102444800,
            "refresh_token": "r",
            "user": {
                "id": USER,
                "aud": "authenticated",
                "email": "probe@example.invalid",
                "app_metadata": {},
                "user_metadata": {"mail_locale": "de"},
                "created_at": "2026-01-01T00:00:00Z",
            },
        }
    )


def pct(values, p):
    """Nearest rank."""
    s = sorted(values)
    return s[max(0, math.ceil(p / 100 * len(s)) - 1)]


def stats(frames):
    build = [b / 1000 for b, _ in frames]
    raster = [r / 1000 for _, r in frames]
    total = [b + r for b, r in zip(build, raster)]
    jank = 100 * sum(t > BUDGET_MS for t in total) / len(total)
    out = {"frames": len(frames)}
    for name, v in (("build", build), ("raster", raster)):
        for p in (50, 90, 99):
            out[f"{name}_p{p}"] = round(pct(v, p), 3)
    out["jank_pct"] = round(jank, 2)
    out["worst_ms"] = round(max(total), 3)
    out["score"] = round(out["build_p90"] + out["raster_p90"] + 2 * jank, 3)
    return out


def launch(binary, cache, port, scenarios):
    server = subprocess.Popen([sys.executable, str(HERE / "fake_supabase.py"), str(port), str(scenarios)])
    try:
        time.sleep(0.7)
        with tempfile.TemporaryDirectory(prefix="hc108-run-") as home:
            data = Path(home, "data", "com.snacklist.app")
            data.mkdir(parents=True)
            (data / "shared_preferences.json").write_text(json.dumps({"flutter.sb-127-auth-token": session()}))
            env = {
                **os.environ,
                "HOME": home,
                "XDG_DATA_HOME": f"{home}/data",
                "XDG_CONFIG_HOME": f"{home}/config",
                "XDG_CACHE_HOME": cache,
                "LANG": "C.UTF-8",
                "LANGUAGE": "de_DE",
            }
            out = subprocess.run([binary], env=env, capture_output=True, text=True, timeout=300)
    finally:
        server.terminate()
        server.wait()
    lines = [l for l in out.stdout.splitlines() if l.startswith("{")]
    if out.returncode != 0 or not lines:
        raise SystemExit(f"ui_perf_probe failed ({out.returncode}): {out.stderr[-3000:]}")
    for line in out.stderr.splitlines():
        if line.startswith("ui_perf_probe:"):
            print(line, file=sys.stderr)
    raw = json.loads(lines[-1])
    flows = {k: {"steps": v["steps"], **stats(v["frames"])} for k, v in raw.items() if isinstance(v, dict)}
    return {
        "flows": flows,
        "idle_frames": raw["idle_frames"],
        "score": round(sum(f["score"] for f in flows.values()) / len(flows), 3),
    }


def main():
    bundle, port, runs, scenarios = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), Path(sys.argv[4])
    binary = str(bundle / "family_groceries")
    with tempfile.TemporaryDirectory(prefix="hc108-cache-") as cache:
        launch(binary, cache, port, scenarios)
        print(json.dumps([launch(binary, cache, port, scenarios) for _ in range(runs)]))


if __name__ == "__main__":
    main()
