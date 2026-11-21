# Lists the custom URL schemes each grocery app in supabase/retailers/retailers.json
# declares in its Android manifest. For every app package it fetches the current APK
# (apkpure, else Aptoide) into a fresh temp dir, reads AndroidManifest.xml and the resource table with
# aapt2 (nothing from the APK runs), and prints JSON: package, APK version, signer,
# and per activity the VIEW intent-filter schemes left after dropping web, OAuth,
# Facebook and payment-SDK schemes.
#
#   python3 -I tool/retailers/app_schemes.py [--only <pkg>...] [--all]
#
# --all keeps the dropped schemes too, marked "dropped".
# AAPT2 overrides the aapt2 path.

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RETAILERS = os.path.join(ROOT, "supabase", "retailers", "retailers.json")
AAPT2 = os.environ.get("AAPT2", os.path.expanduser("~/android-sdk/build-tools/36.0.0/aapt2"))
APTOIDE = "https://ws75.aptoide.com/api/7/app/getMeta?package_name="

SDK_ACTIVITY = re.compile(
    r"RedirectUriReceiver|BrowserTab|CustomTab|paypal|adyen|stripe|klarna|braintree|"
    r"com\.facebook|com\.google|net\.openid|auth0|okta|msal|microsoft\.identity|"
    r"RedirectActivity|OAuth|Auth.*Callback|ThreeDS|3ds|payu|przelewy|blik|mollie|"
    r"androidx\\.|salesforce|sfmc|usabilla|branch\.io|appsflyer|adjust",
    re.I,
)


def dropped_reason(scheme, activity):
    s = scheme.lower()
    if s in ("http", "https", "content", "file"):
        return "web"
    if re.fullmatch(r"fb\d+", s):
        return "facebook"
    if s.startswith("com.googleusercontent.apps") or s.startswith("msauth") or s.endswith(".auth"):
        return "oauth"
    if SDK_ACTIVITY.search(activity):
        return "sdk-activity"
    return None


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "curl/8"}), timeout=120)


def fetch_json(url):
    with get(url) as r:
        return json.load(r)


def aapt2(*args):
    return subprocess.run([AAPT2, *args], capture_output=True, text=True, check=True).stdout


def resource_strings(apk):
    strings, current = {}, None
    for line in aapt2("dump", "resources", apk).splitlines():
        m = re.match(r"\s*resource (0x[0-9a-f]+) string/", line)
        if m:
            current = m.group(1)
            continue
        m = re.match(r'\s*\(\) "(.*)"$', line)
        if m and current and current not in strings:
            strings[current] = m.group(1)
    return strings


def parse_xmltree(text):
    root = {"tag": "root", "attrs": {}, "children": []}
    stack = [(-1, root)]
    for line in text.splitlines():
        indent = len(line) - len(line.lstrip())
        body = line.strip()
        if body.startswith("E: "):
            node = {"tag": body[3:].split(" ")[0], "attrs": {}, "children": []}
            while stack[-1][0] >= indent:
                stack.pop()
            stack[-1][1]["children"].append(node)
            stack.append((indent, node))
        elif body.startswith("A: "):
            m = re.match(r'A: (?:\S*:)?(\w+)\(0x[0-9a-f]+\)=(?:"((?:[^"\\]|\\.)*)"|(@0x[0-9a-f]+)|(\S+))', body)
            if m:
                stack[-1][1]["attrs"][m.group(1)] = m.group(2) if m.group(2) is not None else (m.group(3) or m.group(4))
    return root


def walk(node, tag):
    for child in node["children"]:
        if child["tag"] == tag:
            yield child
        yield from walk(child, tag)


def manifest_apk(path, workdir):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if "AndroidManifest.xml" in names:
            return path
        base = next((n for n in names if n.endswith(".apk") and "config." not in n), None)
        if base is None:
            raise ValueError("no AndroidManifest.xml and no base apk inside")
        return z.extract(base, workdir)


def schemes_of(apk, keep_dropped):
    tree = parse_xmltree(aapt2("dump", "xmltree", "--file", "AndroidManifest.xml", apk))
    manifest = next(walk(tree, "manifest"))
    refs = None
    activities = []
    for tag in ("activity", "activity-alias"):
        for act in walk(manifest, tag):
            name = act["attrs"].get("name", "?")
            found = {}
            for f in walk(act, "intent-filter"):
                actions = {a["attrs"].get("name") for a in walk(f, "action")}
                if "android.intent.action.VIEW" not in actions:
                    continue
                cats = {c["attrs"].get("name") for c in walk(f, "category")}
                datas = [d["attrs"] for d in walk(f, "data")]
                hosts = []
                for d in datas:
                    for key in ("scheme", "host"):
                        v = d.get(key)
                        if v and v.startswith("@"):
                            if refs is None:
                                refs = resource_strings(apk)
                            d[key] = refs.get(v[1:], v)
                    if d.get("host"):
                        hosts.append(d["host"])
                for d in datas:
                    s = d.get("scheme")
                    if not s:
                        continue
                    entry = found.setdefault(s, {"scheme": s, "browsable": False, "hosts": set()})
                    entry["browsable"] |= "android.intent.category.BROWSABLE" in cats
                    entry["hosts"].update(hosts)
            launcher = any(
                c["attrs"].get("name") == "android.intent.category.LAUNCHER" for c in walk(act, "category")
            )
            kept = []
            for e in found.values():
                reason = dropped_reason(e["scheme"], name)
                if reason and not keep_dropped:
                    continue
                e["hosts"] = sorted(e["hosts"])
                if reason:
                    e["dropped"] = reason
                kept.append(e)
            if kept:
                activities.append({"activity": name, "launcher": launcher, "schemes": kept})
    version = manifest["attrs"].get("versionName")
    if version and version.startswith("@"):
        version = (refs if refs is not None else resource_strings(apk)).get(version[1:], version)
    return version, activities


def apkpure_url(pkg):
    return "https://d.apkpure.net/b/XAPK/" + urllib.parse.quote(pkg) + "?version=latest", None


def aptoide_url(pkg):
    data = fetch_json(APTOIDE + urllib.parse.quote(pkg)).get("data") or {}
    f = data.get("file") or {}
    if data.get("package") != pkg or not f.get("path"):
        raise ValueError("not on aptoide")
    return f["path"], f.get("vername")


def signing_certs(apk):
    with zipfile.ZipFile(apk) as z:
        v1 = [n for n in z.namelist() if re.fullmatch(r"META-INF/[^/]+\.(RSA|DSA|EC)", n)]
        if v1:
            pem = subprocess.run(
                ["openssl", "pkcs7", "-inform", "DER", "-print_certs"],
                input=z.read(v1[0]), capture_output=True, check=True,
            ).stdout
            return [pem]
    with open(apk, "rb") as fh:
        data = fh.read()
    eocd = data.rfind(b"PK\x05\x06")
    cd_start = struct.unpack_from("<I", data, eocd + 16)[0]
    if data[cd_start - 16:cd_start] != b"APK Sig Block 42":
        return []
    size = struct.unpack_from("<Q", data, cd_start - 24)[0]
    pos, end = cd_start - size - 8 + 8, cd_start - 24
    while pos < end:
        length, block_id = struct.unpack_from("<QI", data, pos)
        if block_id in (0x7109871A, 0xF05368C0):
            value = memoryview(data)[pos + 12:pos + 8 + length]
            signer = value[8:]
            signed = signer[4:]
            digests_len = struct.unpack_from("<I", signed, 4)[0]
            certs = signed[8 + digests_len:]
            cert_len = struct.unpack_from("<I", certs, 4)[0]
            return [bytes(certs[8:8 + cert_len])]
        pos += 8 + length
    return []


def signer_of(apk):
    certs = signing_certs(apk)
    if not certs:
        return None
    cert = certs[0]
    der = cert.startswith(b"0")
    out = subprocess.run(
        ["openssl", "x509", "-noout", "-subject", "-inform", "DER" if der else "PEM"],
        input=cert, capture_output=True, check=True,
    ).stdout.decode()
    return out.strip().removeprefix("subject=").strip()


def xapk_version(path):
    with zipfile.ZipFile(path) as z:
        if "manifest.json" in z.namelist():
            return json.loads(z.read("manifest.json")).get("version_name")
    return None


def scan(app, keep_dropped):
    pkg = app["android"]
    out = {"package": pkg, "ios": app["ios"], "appName": app["name"]}
    errors = []
    for source, locate in (("apkpure", apkpure_url), ("aptoide", aptoide_url)):
        with tempfile.TemporaryDirectory(prefix=f"app-schemes-{pkg}-") as tmp:
            path = os.path.join(tmp, "download")
            try:
                url, _ = locate(pkg)
                with get(url) as r, open(path, "wb") as fh:
                    shutil.copyfileobj(r, fh)
                apk = manifest_apk(path, tmp)
                version, activities = schemes_of(apk, keep_dropped)
                signer = signer_of(apk)
                version = version or xapk_version(path)
            except Exception as e:
                errors.append(f"{source}: {e}")
                continue
        if errors:
            out["skipped"] = errors
        return {**out, "source": f"{source}:{url}", "apkVersion": version, "signer": signer,
                "activities": activities}
    return {**out, "error": "; ".join(errors)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--only", nargs="*")
    p.add_argument("--all", action="store_true")
    args = p.parse_args()
    with open(RETAILERS) as fh:
        entries = json.load(fh)["entries"]
    apps = {a["android"]: a for e in entries for a in e.get("apps", []) if a.get("android")}
    pkgs = sorted(args.only or apps)
    with concurrent.futures.ThreadPoolExecutor(6) as pool:
        results = list(pool.map(lambda k: scan(apps[k], args.all), pkgs))
    json.dump(results, sys.stdout, indent=1, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
