"""Shared local/CI native configuration validation. Never emits credential values.

Use --config /protected/release.json --platform android|ios --prepare to
materialize a verified configuration; outputs under build/native-release.
This validates consistency, not provider-console access or device acceptance.
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
from pathlib import Path

PRODUCTION_APP = "com.stormdeve.orgami"
PROJECTS = {"production": "orgami-66nxok", "staging": "attendus-staging"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def value(config, name, pattern=None):
    result = config.get(name)
    require(isinstance(result, str) and result.strip() == result and bool(result), f"Missing {name}")
    require(not re.search(r"placeholder|example|replace.me|your[_-]|TODO", result, re.I), f"Placeholder {name}")
    if pattern:
        require(re.fullmatch(pattern, result), f"Invalid {name}")
    return result


def validate(config, platform, root):
    environment = value(config, "environment")
    require(environment in PROJECTS, "Unsupported environment")
    project = value(config, "projectId")
    require(project == PROJECTS[environment], "Firebase environment/project mismatch")
    app = value(config, "applicationId", r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+")
    require((app == PRODUCTION_APP) == (environment == "production"), "Application identity is not isolated")
    domain = value(config, "associatedDomain", r"[a-z0-9]+(?:[.-][a-z0-9]+)*\.[a-z]{2,}")
    require((domain == "attendus.app") == (environment == "production"), "Associated domain is not isolated")
    sender = value(config, "messagingSenderId", r"[1-9][0-9]+")
    maps = value(config, "mapsApiKey", r"AIza[A-Za-z0-9_-]{35}")
    service = root / value(config, "serviceConfigPath")
    raw = service.read_bytes()
    if platform == "android":
        data = json.loads(raw)
        info = data.get("project_info", {})
        require(info.get("project_id") == project and str(info.get("project_number")) == sender, "Android Firebase project mismatch")
        clients = [c for c in data.get("client", []) if c.get("client_info", {}).get("android_client_info", {}).get("package_name") == app]
        require(len(clients) == 1, "Exactly one matching Android Firebase client required")
        client = clients[0]
        app_id = client["client_info"].get("mobilesdk_app_id", "")
        keys = client.get("api_key", [])
        require(len(keys) == 1, "Exactly one Android API key required")
        api = keys[0].get("current_key", "")
        require(any(c.get("client_type") == 3 and c.get("client_id", "").endswith(".apps.googleusercontent.com") for c in client.get("oauth_client", [])), "Google web OAuth client missing")
        fingerprint = value(config, "playAppSigningSha256", r"(?:[A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}")
        require(len(set(fingerprint.replace(":", "").lower())) > 2, "Placeholder Play signing certificate")
        bucket = info.get("storage_bucket")
    else:
        data = plistlib.loads(raw)
        require(data.get("PROJECT_ID") == project and data.get("GCM_SENDER_ID") == sender and data.get("BUNDLE_ID") == app, "iOS Firebase identity mismatch")
        app_id, api, bucket = data.get("GOOGLE_APP_ID", ""), data.get("API_KEY", ""), data.get("STORAGE_BUCKET")
        client = data.get("CLIENT_ID", "")
        require(client.endswith(".apps.googleusercontent.com") and data.get("REVERSED_CLIENT_ID") == ".".join(reversed(client.split("."))), "iOS OAuth URL scheme mismatch")
        value(config, "appleTeamId", r"[A-Z0-9]{10}")
    require(re.fullmatch(rf"1:{sender}:{platform}:[a-f0-9]+", app_id), "Firebase app/sender/platform mismatch")
    require(re.fullmatch(r"AIza[A-Za-z0-9_-]{35}", api), "Invalid Firebase API key")
    require(bucket in (f"{project}.appspot.com", f"{project}.firebasestorage.app"), "Firebase Storage project mismatch")
    require(config.get("appCheckProvider") == ("playIntegrity" if platform == "android" else "deviceCheck"), "Release App Check provider mismatch")
    return {"environment": environment, "applicationId": app, "projectId": project,
            "serviceSha256": hashlib.sha256(raw).hexdigest(), "platform": platform}, {
        "ATTENDUS_FIREBASE_ENV": environment, "ATTENDUS_NATIVE_FIREBASE_API_KEY": api,
        "ATTENDUS_NATIVE_FIREBASE_APP_ID": app_id, "ATTENDUS_NATIVE_FIREBASE_SENDER_ID": sender,
        "ATTENDUS_NATIVE_FIREBASE_PROJECT_ID": project, "ATTENDUS_NATIVE_FIREBASE_STORAGE_BUCKET": bucket,
        "ATTENDUS_NATIVE_APPLICATION_ID": app,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--platform", required=True, choices=["android", "ios"])
    parser.add_argument("--prepare", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    manifest, defines = validate(config, args.platform, args.config.parent)
    manifest["configSha256"] = hashlib.sha256(args.config.read_bytes()).hexdigest()
    output = Path("build/native-release")
    output.mkdir(parents=True, exist_ok=True)
    (output / f"{args.platform}-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.prepare:
        if os.environ.get("GITHUB_ENV"):
            # Register nested credential fields before a later runner step displays its environment.
            print("::add-mask::" + config["mapsApiKey"])
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
                env.write(f"ATTENDUS_APPLICATION_ID={config['applicationId']}\n")
                env.write(f"ATTENDUS_ASSOCIATED_DOMAIN={config['associatedDomain']}\n")
                env.write(f"GOOGLE_MAPS_{args.platform.upper()}_API_KEY={config['mapsApiKey']}\n")
                if args.platform == "ios":
                    env.write(f"TEAM_ID={config['appleTeamId']}\n")
        (output / "defines.json").write_text(json.dumps(defines))
        service = args.config.parent / config["serviceConfigPath"]
        if args.platform == "android":
            Path("android/app/google-services.json").write_bytes(service.read_bytes())
            Path("android/native-release.properties").write_text(f"applicationId={config['applicationId']}\nassociatedDomain={config['associatedDomain']}\n")
        else:
            Path("ios/Runner/GoogleService-Info.plist").write_bytes(service.read_bytes())
            info = plistlib.loads(Path("ios/Runner/Info.plist").read_bytes())
            data = plistlib.loads(service.read_bytes())
            info["CFBundleURLTypes"] = [{"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": [data["REVERSED_CLIENT_ID"]]}]
            Path("ios/Runner/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
            Path("ios/Flutter/NativeEnvironment.xcconfig").write_text(f"ATTENDUS_APPLICATION_ID = {config['applicationId']}\nATTENDUS_ASSOCIATED_DOMAIN = {config['associatedDomain']}\n")
    print(f"{args.platform} {manifest['environment']} configuration consistency verified; provider/device qualification remains required.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError):
        raise SystemExit("Native preflight failed: protected configuration is absent, invalid, or inconsistent. Validate configuration locally; values are suppressed.") from None
