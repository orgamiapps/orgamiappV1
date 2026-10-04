"""Inventory source surfaces without reading secrets or contacting Firebase."""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]

# A report establishes subsystem review, never individual-file execution.
REVIEW_REPORTS = {
    "screen": "docs/debugging-client-20261003.md",
    "client": "docs/debugging-client-20261003.md",
    "backend": "docs/debugging-backend-20261003.md",
    "rules": "docs/debugging-backend-20261003.md",
    "admin": "docs/debugging-platform-20261003.md",
    "platform": "docs/debugging-platform-20261003.md",
    "web-delivery": "docs/debugging-platform-20261003.md",
    "tooling": "docs/debugging-ledger-20261003.md",
    "configuration": "docs/debugging-ledger-20261003.md",
    "test": "docs/debugging-ledger-20261003.md",
    "asset": "docs/debugging-ledger-20261003.md",
}


def inventory():
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
    ).decode().split("\0")
    entries = []
    collections = {}
    routes = {}
    storage = {}
    flags = {}
    for name in sorted(set(tracked)):
        path = ROOT / name
        asset = name.startswith(("assets/", "web/icons/", "web/splash/")) or (
            name.startswith("web/") and path.suffix.lower() in {".svg", ".png", ".jpg", ".webp", ".ico"})
        if not path.is_file() or (not asset and path.suffix not in {".dart", ".js", ".cjs", ".yml", ".rules",
                ".py", ".ps1", ".xml", ".gradle", ".plist", ".entitlements", ".xcconfig",
                ".pbxproj", ".json", ".yaml", ".html", ".css", ".swift", ".kt", ".kts",
                ".java", ".m", ".mm", ".h", ".cpp", ".cc", ".c", ".cmake", ".rc",
                ".sh", ".bat", ".cmd", ".config", ".props", ".vcxproj", ".sln", ".lock", ".txt"}):
            continue
        if asset:
            kind = "asset"
        elif name.startswith("lib/screens/"):
            kind = "screen"
        elif name.startswith("lib/"):
            kind = "client"
        elif name.startswith(("apps/attendus_admin/lib/", "attendus_admin/lib/")):
            kind = "admin"
        elif name.startswith(("functions/test/", "test/", "integration_test/", "test_driver/", "tests/")) or "/test/" in name:
            kind = "test"
        elif name.startswith("functions/"):
            kind = "backend"
        elif name.startswith("web/"):
            kind = "web-delivery"
        elif name.startswith((".github/workflows/", "tools/", "scripts/")):
            kind = "tooling"
        elif name.startswith(("android/", "ios/", "windows/", "macos/", "linux/",
                              "apps/attendus_admin/windows/", "apps/attendus_admin/android/",
                              "apps/attendus_admin/ios/", "apps/attendus_admin/macos/",
                              "apps/attendus_admin/linux/")):
            kind = "platform"
        elif name.endswith(".rules"):
            kind = "rules"
        elif name in {"firebase.json", "firebase.test.json", "firestore.indexes.json"} or path.name in {"pubspec.yaml", "pubspec.lock"}:
            kind = "configuration"
        else:
            continue
        content = path.read_bytes()
        text = "" if asset else content.decode("utf-8", errors="replace")
        entries.append({"path": name, "kind": kind, "sha256": hashlib.sha256(content).hexdigest(),
                        "reviewStatus": "subsystem-report-linked; individual-file-coverage-not-asserted",
                        "reviewEvidence": REVIEW_REPORTS[kind],
                        "runtimeStatus": "see-suite-and-journey-evidence; not-implied-by-inventory"})
        for collection in re.findall(r"\.collection\(\s*['\"]([^'\"]+)['\"]", text):
            collections.setdefault(collection, set()).add(name)
        for route in re.findall(r"(?:path|routeName)\s*[:=]\s*['\"]([^'\"]+)['\"]", text):
            routes.setdefault(route, set()).add(name)
        for prefix in re.findall(r"\.(?:ref|child)\(\s*['\"]([^'\"]+)['\"]", text):
            storage.setdefault(prefix, set()).add(name)
        for flag in re.findall(r"\b(?:ATTENDUS|ATTENDANCE)_[A-Z0-9_]+\b", text):
            flags.setdefault(flag, set()).add(name)
    exports = (ROOT / "functions/index.js").read_text(encoding="utf-8")
    return {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "note": "Inventory is not review or test evidence. Dynamic collections/routes require manual review.",
        "surfaces": entries,
        "functionExports": sorted(set(re.findall(r"exports\.([A-Za-z0-9_]+)\s*=", exports))),
        "literalCollections": {k: sorted(v) for k, v in sorted(collections.items())},
        "literalRoutes": {k: sorted(v) for k, v in sorted(routes.items())},
        "storageReferenceCandidates": {k: sorted(v) for k, v in sorted(storage.items())},
        "environmentFlagReferences": {k: sorted(v) for k, v in sorted(flags.items())},
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    result = inventory()
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "surfaces": len(result["surfaces"]),
                      "exports": len(result["functionExports"]), "collections": len(result["literalCollections"])}))
