#!/usr/bin/env python3
"""Repository hygiene + asset manifest check (CI and local).

  python3 -I tools/check_repo.py            # verify, exit 1 on problems
  python3 -I tools/check_repo.py --write    # regenerate assets/manifest.json hashes
"""
import hashlib, json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEGACY = "legacy/inner_core_95_v7_2_4_faction_palettes_icon_safety_police_cockpit.html"
LEGACY_SHA256 = "405177fe6973ebede7a06e971fbef40d28a7648771e8445ec5bf2d79473a5036"
MANIFEST = "assets/manifest.json"
MAX_BYTES = 8 * 1024 * 1024
FORBIDDEN_EXT = (".keystore", ".jks", ".p12", ".pem", ".env", ".apk", ".aab")
FORBIDDEN_NAMES = ("export_credentials.cfg", "credentials.json", ".env")


def sha256(path):
    with open(os.path.join(ROOT, path), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def tracked():
    try:
        out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        return [l for l in out.splitlines() if l]
    except Exception:
        return []


def main():
    problems = []
    files = tracked()
    if os.path.exists(os.path.join(ROOT, LEGACY)):
        if sha256(LEGACY) != LEGACY_SHA256:
            problems.append(f"legacy reference modified: {LEGACY} (must stay byte-identical)")
    else:
        problems.append(f"legacy reference missing: {LEGACY}")
    for f in files:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        if os.path.getsize(p) > MAX_BYTES:
            problems.append(f"file too large for repo (>8MB): {f}")
        low = f.lower()
        if low.endswith(FORBIDDEN_EXT) or os.path.basename(low) in FORBIDDEN_NAMES:
            problems.append(f"forbidden file type tracked (secrets/builds): {f}")
    with open(os.path.join(ROOT, MANIFEST)) as fh:
        manifest = json.load(fh)
    listed = set()
    for a in manifest["assets"]:
        listed.add(a["path"])
        if not os.path.exists(os.path.join(ROOT, a["path"])):
            problems.append(f"manifest asset missing: {a['path']}")
            continue
        h = sha256(a["path"])
        if "--write" in sys.argv:
            a["sha256"] = h
        elif a.get("sha256") != h:
            problems.append(f"asset hash changed without manifest update: {a['path']}")
        for k in ("source", "provenance", "use"):
            if not a.get(k):
                problems.append(f"manifest entry lacks '{k}': {a['path']}")
    for f in files or []:
        if f.startswith("assets/") and f.endswith((".png", ".gif", ".wav", ".ogg", ".ttf", ".otf")) and f not in listed:
            problems.append(f"asset not in manifest: {f}")
    if "--write" in sys.argv:
        with open(os.path.join(ROOT, MANIFEST), "w") as fh:
            json.dump(manifest, fh, indent=1)
            fh.write("\n")
        print("manifest hashes written")
    if problems:
        print("Repository check FAILED:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print(f"Repository check OK ({len(files)} tracked files, {len(manifest['assets'])} manifest assets)")


if __name__ == "__main__":
    main()
