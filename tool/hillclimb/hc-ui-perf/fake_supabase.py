#!/usr/bin/env python3
"""The Supabase endpoints the list, the add sheet and a tick call, answered
from one fixed household built from the job 18 fixtures (no real data, no
network): the ten stores of test/fixtures/scenarios/many-stores.yaml with
their walk orders and hidden categories, the default categories, and 300
open items, the names of solo-long-list.yaml in their categories, spread
over the stores and no store. Writes change the in-memory rows, so a tick
or an add is acknowledged as the database would. The realtime socket
answers 404, so the list runs offline-marked, as on a flaky start.

    fake_supabase.py <port> <scenarios dir>
    fake_supabase.py dump <scenarios dir>     # the household as JSON, for hc-list-cpu
"""

import json
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import yaml

USER = "00000000-0000-4000-8000-000000000001"
HOUSEHOLD = "00000000-0000-4000-8000-0000000000aa"
LIST = "00000000-0000-4000-8000-0000000000bb"
STAMP = "2026-11-01T10:00:00+00:00"
ITEM_COUNT = 300
SEED = 0

# public.seed_household's categories, plus many-stores.yaml's own.
SEED_CATEGORIES = [
    ("Obst & Gemüse", "produce", 10),
    ("Brot & Backwaren", "bakery", 20),
    ("Kühlregal", "chilled", 30),
    ("Fleisch/Wurst/Fisch", "meat", 40),
    ("Vorrat & Konserven", "pantry", 50),
    ("Süßes & Snacks", "sweets", 60),
    ("Getränke", "drinks", 70),
    ("Tiefkühl", "frozen", 80),
    ("Haushalt", "household", 90),
    ("👶 Drogerie", "drugstore", 100),
    ("Sonstiges", "other", 1000),
]
# Every name once: a list holds one open item per thing.
VARIANTS = ["", "Bio-", "Frische ", "Regionale ", "Große "]
BRANDS = [None, None, "Ja!", None, "Alnatura"]


def uid(kind, i):
    return f"00000000-0000-4000-8000-{kind:02d}{i:010d}"


def load(scenarios):
    many = yaml.safe_load((scenarios / "many-stores.yaml").read_text())["households"][0]
    categories = [
        {"id": uid(12, i), "name": n, "sort_order": o, "seed_key": k}
        for i, (n, k, o) in enumerate(SEED_CATEGORIES)
    ]
    for j, name in enumerate(many["categories"]["add"]):
        categories.append({"id": uid(12, 50 + j), "name": name, "sort_order": 1010 + j, "seed_key": None})
    by_name = {c["name"]: c["id"] for c in categories}
    stores, layout = [], []
    for i, s in enumerate(many["stores"]):
        sid = uid(13, i)
        stores.append({"id": sid, "name": s["name"], "sort_order": 10 * (i + 1), "seed_key": None})
        for o, cat in enumerate(s.get("layout", [])):
            layout.append({"store_id": sid, "category_id": by_name[cat], "sort_order": o, "hidden": False})
        for cat in s.get("hidden", []):
            layout.append({"store_id": sid, "category_id": by_name[cat], "sort_order": 999, "hidden": True})

    # solo-long-list.yaml: a "# <category>" comment heads the items under it.
    names, current = [], None
    in_items = False
    for line in (scenarios / "solo-long-list.yaml").read_text().splitlines():
        if line.strip() == "items:":
            in_items = True
            continue
        if not in_items:
            continue
        if m := re.match(r"\s+# (.+)$", line):
            current = m.group(1).strip()
        elif m := re.match(r"\s+- (.+)$", line):
            entry = yaml.safe_load(m.group(1))
            entry = entry if isinstance(entry, dict) else {"name": entry}
            names.append((entry["name"], entry.get("quantity"), by_name[current]))

    store_ids = [None] + [s["id"] for s in stores]
    items = {}
    for i in range(ITEM_COUNT):
        base, quantity, category = names[i % len(names)]
        name = VARIANTS[i // len(names)] + base
        brand = BRANDS[i % len(BRANDS)]
        row = {
            "id": uid(1, i),
            "name": name,
            "quantity": quantity,
            "brand": brand,
            "properties": None,
            "category_id": category,
            "store_id": store_ids[(i * 7) % len(store_ids)],
            "sort_key": None,
            "status": "active",
            "created_at": STAMP,
            "updated_at": STAMP,
            "bought_at": None,
            "added_by": USER,
            "categorized_via": "seed",
            "canonical_key": name.lower(),
            "list_id": LIST,
        }
        items[row["id"]] = row
    usuals = [
        {"name": n, "quantity": q, "due": k % 5 == 0, "last_used": STAMP}
        for k, (n, q, _) in enumerate(names[:40])
    ]
    tables = {
        "categories": categories,
        "stores": stores,
        "store_category_order": layout,
        "profiles": [{"id": USER, "display_name": "Tara"}],
        "entitlements": [],
        "user_entitlements": [],
        "item_claims": [],
        "lists": [{"id": LIST, "name": "Einkaufsliste", "position": 0, "seed_key": "main"}],
        "households": [{"currency": "EUR"}],
    }
    return tables, items, usuals, [c["id"] for c in categories]


TABLES, ITEMS, USUALS, CATEGORY_IDS = load(Path(sys.argv[2]))
CLOCK = [0]


def tick_clock():
    CLOCK[0] += 1
    return f"2026-11-02T10:{CLOCK[0] // 60 % 60:02d}:{CLOCK[0] % 60:02d}+00:00"


LOG = os.environ.get("FAKE_SUPABASE_LOG")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def log_request(self, code="-", size="-"):
        # FAKE_SUPABASE_LOG=<file>: one line per answer (wall-clock µs, method, path, status), so
        # a call the app makes that this fake does not know shows up instead of failing silently.
        if LOG:
            with open(LOG, "a") as log:
                log.write(f"{time.time_ns() // 1000} {self.command} {self.path} {int(code)}\n")

    def _send(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")

    def _rows(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        table = url.path.removeprefix("/rest/v1/")
        if table == "household_members":
            if "user_id" in query:
                return {"households": {"id": HOUSEHOLD, "name": "Familie Kaufmann"}}
            return [{"user_id": USER, "role": "owner"}]
        if table == "items":
            if "id" in query:
                target = query["id"][0].removeprefix("eq.")
                return [ITEMS[target]] if target in ITEMS else []
            status = query.get("status", ["eq.active"])[0].removeprefix("eq.")
            rows = [r for r in ITEMS.values() if r["status"] == status]
            if status == "bought":
                rows = sorted(rows, key=lambda r: r["bought_at"] or "", reverse=True)[:50]
            return rows
        return TABLES.get(table)

    def do_GET(self):
        if not self.path.startswith("/rest/v1/"):
            return self._send(404, {"message": "not here"})
        rows = self._rows()
        if rows is None:
            return self._send(404, {"message": "unknown table"})
        single = "vnd.pgrst.object" in self.headers.get("Accept", "")
        if single:
            rows = rows if isinstance(rows, dict) else (rows[0] if rows else None)
        elif isinstance(rows, dict):
            rows = [rows]
        self._send(200, rows)

    def do_HEAD(self):
        self._send(200, [])

    def do_POST(self):
        body = self._body()
        path = urlparse(self.path).path
        if path == "/rest/v1/rpc/put_item":
            row = {
                "id": body["p_id"],
                "name": body["p_name"],
                "quantity": body.get("p_quantity"),
                "brand": body.get("p_brand"),
                "properties": body.get("p_properties"),
                "category_id": body.get("p_category")
                or CATEGORY_IDS[sum(map(ord, body["p_name"])) % len(CATEGORY_IDS)],
                "store_id": body.get("p_store"),
                "sort_key": body.get("p_sort_key"),
                "status": body.get("p_status") or "active",
                "created_at": tick_clock(),
                "bought_at": None,
                "added_by": USER,
                "categorized_via": "classifier",
                "canonical_key": body["p_name"].lower(),
                "list_id": body.get("p_list") or LIST,
            }
            row["updated_at"] = row["created_at"]
            ITEMS[row["id"]] = row
            return self._send(200, row)
        # Since job 169b (several households per user) the session and the catalog read these.
        if path == "/rest/v1/rpc/my_households":
            return self._send(
                200,
                [
                    {
                        "id": HOUSEHOLD,
                        "name": "Familie Kaufmann",
                        "is_default": True,
                        "member_count": 1,
                        "open_count": sum(r["status"] == "active" for r in ITEMS.values()),
                        "kind": "family",
                        "role": "owner",
                        "premium": False,
                        "join_approval": False,
                    }
                ],
            )
        if path == "/rest/v1/rpc/household_members_of":
            return self._send(200, [{"user_id": USER, "display_name": "Tara", "role": "owner"}])
        if path == "/rest/v1/rpc/suggest_items":
            return self._send(200, USUALS)
        if path == "/rest/v1/rpc/suggest_entries":
            text = (body or {}).get("p_text", "")
            return self._send(200, [{"source": "typed", "name": text}] if text.strip() else [])
        self._send(200, [])

    def do_PUT(self):
        self._body()
        self._send(404, {"message": "not here"})

    def do_PATCH(self):
        body = self._body()
        target = parse_qs(urlparse(self.path).query).get("id", [""])[0].removeprefix("eq.")
        row = ITEMS.get(target)
        if row is None:
            return self._send(200, [])
        row.update(body)
        row["updated_at"] = tick_clock()
        row["bought_at"] = row["updated_at"] if row["status"] == "bought" else None
        self._send(200, [row])

    def do_DELETE(self):
        target = parse_qs(urlparse(self.path).query).get("id", [""])[0].removeprefix("eq.")
        row = ITEMS.pop(target, None)
        self._send(200, [{"id": target}] if row else [])


class Server(ThreadingHTTPServer):
    # The app opens about eight connections at once (job 100: the default
    # backlog of 5 drops SYNs).
    request_queue_size = 128

    def handle_error(self, request, client_address):
        # The probe exits with connections open; that reset is no error. Its traceback would
        # also land in measure.sh's JSON (xvfb-run sends stderr to stdout).
        if not isinstance(sys.exc_info()[1], ConnectionError):
            super().handle_error(request, client_address)


if __name__ == "__main__":
    if sys.argv[1] == "dump":
        keys = ("categories", "stores", "store_category_order", "lists")
        json.dump({**{k: TABLES[k] for k in keys}, "items": list(ITEMS.values()), "usuals": USUALS}, sys.stdout)
        sys.exit(0)
    Server(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
