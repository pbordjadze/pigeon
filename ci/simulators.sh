#!/usr/bin/env bash
# Prints one "<kind> <udid> <model> <runtime>" line per simulator wanted.
#   ci/simulators.sh [iphone|ipad ...]   (default: iphone)
# Picks the newest iOS runtime and the newest iPhone Pro device type (and the largest iPad Pro,
# should one be asked for), and uses the runner image's device of that type if it has one, else
# creates a Pigeon-<kind>.
set -euo pipefail
python3 - "$@" <<'PY'
import json, subprocess, re, sys
wanted = sys.argv[1:] or ["iphone"]
def sim(*a): return subprocess.run(["xcrun", "simctl", *a], check=True, capture_output=True, text=True).stdout
runtimes = [r for r in json.loads(sim("list", "runtimes", "-j"))["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
runtime = sorted(runtimes, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
types = runtime.get("supportedDeviceTypes") or json.loads(sim("list", "devicetypes", "-j"))["devicetypes"]
names = [t["name"] for t in types]
def pick(patterns):
    for p in patterns:
        c = [t for t in types if re.fullmatch(p, t["name"])]
        if c: return c[-1]
    raise SystemExit("no device type for %s in %s" % (patterns, names))
phone = pick([r"iPhone 17 Pro", r"iPhone 1\d Pro", r"iPhone .*Pro"])
pad = pick([r"iPad Pro 13-inch \(M5\)", r"iPad Pro 13-inch \(M\d\)", r"iPad Pro 13-inch.*", r"iPad Pro.*"])
devices = json.loads(sim("list", "devices", "available", "-j"))["devices"].get(runtime["identifier"], [])
for kind, t in (("iphone", phone), ("ipad", pad)):
    if kind not in wanted: continue
    # Reuse a device the runner image already created (its data container exists, so the
    # first boot is much faster than for a brand-new device).
    existing = [d for d in devices if d["deviceTypeIdentifier"] == t["identifier"]]
    if existing:
        print(kind, existing[0]["udid"], t["name"].replace(" ", "_"), runtime["version"])
        continue
    name = "Pigeon-" + kind
    udid = sim("create", name, t["identifier"], runtime["identifier"]).strip()
    print(kind, udid, t["name"].replace(" ", "_"), runtime["version"])
PY
