#!/usr/bin/env python3
"""The few Supabase endpoints the app calls from launch until its list shows,
answered from a fixed household (no real data, no network). The realtime
socket answers 404, so the list runs offline-marked, as on a flaky start.

    fake_supabase.py <port>
"""

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

USER = "00000000-0000-4000-8000-000000000001"
HOUSEHOLD = "00000000-0000-4000-8000-0000000000aa"
LIST = "00000000-0000-4000-8000-0000000000bb"
CATEGORIES = ["Obst & Gemüse", "Brot & Backwaren", "Milchprodukte", "Fleisch & Fisch", "Getränke", "Haushalt"]
NAMES = [
    "Äpfel", "Bananen", "Tomaten", "Gurke", "Brötchen", "Vollkornbrot", "Milch", "Joghurt",
    "Butter", "Käse", "Hähnchenbrust", "Lachs", "Mineralwasser", "Orangensaft", "Kaffee",
    "Spülmittel", "Küchenrolle", "Müllbeutel", "Paprika", "Zwiebeln", "Quark", "Eier",
    "Hackfleisch", "Apfelschorle",
]
STAMP = "2026-11-01T10:00:00+00:00"


def category_id(i):
    return f"00000000-0000-4000-8000-0000000c{i:04d}"


def item(i, name, status="active"):
    return {
        "id": f"00000000-0000-4000-8000-00000001{i:04d}",
        "name": name,
        "quantity": "2" if i % 5 == 0 else None,
        "brand": None,
        "properties": None,
        "category_id": category_id(i % len(CATEGORIES)),
        "store_id": None,
        "sort_key": None,
        "status": status,
        "created_at": STAMP,
        "updated_at": STAMP,
        "bought_at": None,
        "added_by": USER,
        "categorized_via": "seed",
        "canonical_key": name.lower(),
        "list_id": LIST,
    }


ITEMS = [item(i, n) for i, n in enumerate(NAMES)]
TABLES = {
    "categories": [
        {"id": category_id(i), "name": n, "sort_order": i, "seed_key": None} for i, n in enumerate(CATEGORIES)
    ],
    "stores": [],
    "store_category_order": [],
    "profiles": [{"id": USER, "display_name": "Peter"}],
    "entitlements": [],
    "user_entitlements": [],
    "item_claims": [],
    "lists": [{"id": LIST, "name": "Einkaufsliste", "position": 0, "seed_key": "main"}],
    "households": [{"currency": "EUR"}],
}
# What the app reads through rpc since job 169b (several households per user); any other rpc
# answers [].
RPCS = {
    "my_households": [
        {
            "id": HOUSEHOLD,
            "name": "Zuhause",
            "is_default": True,
            "member_count": 1,
            "open_count": len(ITEMS),
            "kind": "family",
            "role": "owner",
            "premium": False,
            "join_approval": False,
        }
    ],
    "household_members_of": [{"user_id": USER, "display_name": "Peter", "role": "owner"}],
}


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

    def _rows(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        table = url.path.removeprefix("/rest/v1/")
        if table == "household_members":
            if "user_id" in query:
                return {"households": {"id": HOUSEHOLD, "name": "Zuhause"}}, query
            return [{"user_id": USER, "role": "owner"}], query
        if table == "items":
            return ([] if query.get("status") == ["eq.bought"] else ITEMS), query
        return TABLES.get(table), query

    def do_GET(self):
        if not self.path.startswith("/rest/v1/"):
            return self._send(404, {"message": "not here"})
        rows, _ = self._rows()
        if rows is None:
            return self._send(404, {"message": "unknown table"})
        single = "vnd.pgrst.object" in self.headers.get("Accept", "")
        if isinstance(rows, dict) and not single:
            rows = [rows]
        self._send(200, rows)

    def do_HEAD(self):
        self._send(200, [])

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self._send(200, RPCS.get(urlparse(self.path).path.removeprefix("/rest/v1/rpc/"), []))

    def do_PUT(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self._send(404, {"message": "not here"})

    def do_PATCH(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        target = parse_qs(urlparse(self.path).query).get("id", [""])[0].removeprefix("eq.")
        rows = [{**row, **body} for row in ITEMS if row["id"] == target]
        self._send(200, rows)


class Server(ThreadingHTTPServer):
    # The app opens about eight connections at once; with the default backlog of 5 the kernel
    # drops a SYN now and then, and the client resends it a second later.
    request_queue_size = 128

    def handle_error(self, request, client_address):
        # The probe exits with connections open; that reset is no error. Its traceback would
        # also land in measure.sh's JSON (xvfb-run sends stderr to stdout).
        if not isinstance(sys.exc_info()[1], ConnectionError):
            super().handle_error(request, client_address)


if __name__ == "__main__":
    Server(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
