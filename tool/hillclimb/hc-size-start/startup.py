#!/usr/bin/env python3
"""Launches the startup probe build <runs> times (after one discarded warm-up)
against fake_supabase.py and prints one JSON line: the median and every run's
first_frame_ms, list_shown_ms and interactive_ms, counted from the moment
before the process is spawned. Each launch gets a fresh data directory holding
only a signed-in session (a returning user whose app was killed); the cache
directory (Mesa's shader cache, fontconfig's) is shared by the launches and
filled by the warm-up, as that user's would be. Run it inside an X server
(xvfb-run).

    startup.py <bundle dir> <port> <runs>
"""

import base64
import json
import os
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
USER = "00000000-0000-4000-8000-000000000001"


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


def launch(binary, cache):
    with tempfile.TemporaryDirectory(prefix="hc100-start-") as home:
        data = Path(home, "data", "com.snacklist.app")
        data.mkdir(parents=True)
        (data / "shared_preferences.json").write_text(json.dumps({"flutter.sb-127-auth-token": session()}))
        env = {
            **os.environ,
            "HOME": home,
            "XDG_DATA_HOME": f"{home}/data",
            "XDG_CONFIG_HOME": f"{home}/config",
            "XDG_CACHE_HOME": cache,
        }
        start = time.time_ns() // 1000
        out = subprocess.run([binary], env=env, capture_output=True, text=True, timeout=90)
        lines = [l for l in out.stdout.splitlines() if l.startswith("{")]
        if out.returncode != 0 or not lines:
            raise SystemExit(f"startup probe failed ({out.returncode}): {out.stderr[-2000:]}")
        marks = json.loads(lines[-1])
        return {k: round((marks[k] - start) / 1000, 1) for k in ("first_frame", "list_shown", "interactive")}


def main():
    bundle, port, runs = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    server = subprocess.Popen([sys.executable, str(HERE / "fake_supabase.py"), str(port)])
    try:
        time.sleep(0.5)
        binary = str(bundle / "family_groceries")
        with tempfile.TemporaryDirectory(prefix="hc100-cache-") as cache:
            launch(binary, cache)
            samples = [launch(binary, cache) for _ in range(runs)]
    finally:
        server.terminate()
    print(
        json.dumps(
            {
                **{f"{k}_ms": statistics.median(s[k] for s in samples) for k in samples[0]},
                "samples": samples,
            }
        )
    )


if __name__ == "__main__":
    main()
