"""Materialize protected CI signing inputs; never print credential values."""
import base64
import json
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
from datetime import datetime, timezone


def required(name):
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"Missing protected release input: {name}")
    return value


def main():
    team = required("TEAM_ID")
    app = required("ATTENDUS_APPLICATION_ID")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", app):
        raise RuntimeError("Invalid release application identifier")
    if not re.fullmatch(r"[A-Z0-9]{10}", team) or not re.fullmatch(r"[1-9][0-9]*", required("BUILD_NUMBER")):
        raise RuntimeError("Invalid release identity")
    temp = Path(required("RUNNER_TEMP"))
    certificate = temp / "certificate.p12"
    profile = temp / "profile.mobileprovision"
    certificate.write_bytes(base64.b64decode(required("CERTIFICATE"), validate=True))
    profile.write_bytes(base64.b64decode(required("PROFILE"), validate=True))
    provision = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(profile)]))
    if provision.get("TeamIdentifier") != [team] or provision["Entitlements"].get("application-identifier") != f"{team}.{app}":
        raise RuntimeError("Provisioning profile does not match the release app")
    if provision["Entitlements"].get("get-task-allow") or provision.get("ProvisionedDevices") or provision.get("ProvisionsAllDevices"):
        raise RuntimeError("App Store distribution profile required")
    if provision["Entitlements"].get("aps-environment") != "production" or "Default" not in provision["Entitlements"].get("com.apple.developer.applesignin", []):
        raise RuntimeError("Distribution push and Apple sign-in capabilities required")
    domains = provision["Entitlements"].get("com.apple.developer.associated-domains", [])
    if "*" not in domains and f"applinks:{required('ATTENDUS_ASSOCIATED_DOMAIN')}" not in domains:
        raise RuntimeError("Provisioning profile lacks the selected associated domain")
    expiry = provision.get("ExpirationDate")
    if not expiry or expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise RuntimeError("Provisioning profile is expired")
    profiles = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    profiles.mkdir(parents=True, exist_ok=True)
    (profiles / f"{provision['UUID']}.mobileprovision").write_bytes(profile.read_bytes())
    keychain = str(temp / "attendus-signing.keychain-db")
    password = required("KEYCHAIN_PASSWORD")
    for command in [
        ["security", "create-keychain", "-p", password, keychain],
        ["security", "set-keychain-settings", "-lut", "21600", keychain],
        ["security", "unlock-keychain", "-p", password, keychain],
        ["security", "import", str(certificate), "-P", required("CERTIFICATE_PASSWORD"), "-A", "-t", "cert", "-f", "pkcs12", "-k", keychain],
        ["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-k", password, keychain],
        ["security", "list-keychains", "-d", "user", "-s", keychain],
    ]:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning", keychain], text=True)
    profile_certificates = provision.get("DeveloperCertificates", [])
    if not any(hashlib.sha1(cert).hexdigest().upper() in identities for cert in profile_certificates):
        raise RuntimeError("Imported signing identity does not match the provisioning profile")
    api = json.loads(required("API_KEY"))
    if not all(api.get(k) for k in ("key_id", "issuer_id", "key")):
        raise RuntimeError("App Store Connect API key configuration incomplete")
    (temp / "appstore-api.json").write_text(json.dumps(api), encoding="utf-8")
    with (temp / "ExportOptions.plist").open("wb") as output:
        plistlib.dump({"method": "app-store-connect", "teamID": team, "signingStyle": "manual", "provisioningProfiles": {app: provision["UUID"]}}, output)
    maps_key = required("GOOGLE_MAPS_IOS_API_KEY")
    if not re.fullmatch(r"AIza[A-Za-z0-9_-]{35}", maps_key):
        raise RuntimeError("Invalid Maps release configuration")
    Path("ios/Flutter/ProtectedRelease.xcconfig").write_text(
        f"DEVELOPMENT_TEAM = {team}\nCODE_SIGN_STYLE = Manual\nCODE_SIGN_IDENTITY = Apple Distribution\nCODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution\nPROVISIONING_PROFILE_SPECIFIER = {provision['UUID']}\nGOOGLE_MAPS_IOS_API_KEY = {maps_key}\n", encoding="utf-8")
    print("Protected iOS signing configuration prepared.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError:
        raise SystemExit("Signing tool rejected protected inputs; inspect environment configuration.") from None
