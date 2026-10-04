"""Validate release graphs without dispatching workflows or mutating cloud state."""
import copy
from pathlib import Path
import re
import unittest
import yaml

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"
WEB_REQUIRED = {"flutter-quality", "functions", "firebase-emulators", "secret-scan", "browser-journeys"}
REQUIRED = WEB_REQUIRED | {"web-release", "android-release", "ios-release", "admin-desktop-integration"}
MUTATION = re.compile(r"firebase deploy|action-hosting-deploy@|fastlane (?:supply|pilot upload)|web_release_pipeline.js (?:stage|promote)")
GITLEAKS_ARCHIVE = "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz"
GITLEAKS_SHA256 = "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"


def load_workflows():
    return {path.name: yaml.safe_load(path.read_text(encoding="utf-8")) for path in WORKFLOWS.glob("*.yml")}


def dependencies(job):
    value = job.get("needs", [])
    return [value] if isinstance(value, str) else value


def runs(job):
    return "\n".join(step.get("run", "") for step in job.get("steps", []))


def validate_secret_scan(job):
    steps = job.get("steps", [])
    checkouts = [step for step in steps if step.get("uses", "").startswith("actions/checkout@")]
    scans = [step for step in steps if '"$tool_dir/gitleaks" git ' in step.get("run", "")]
    if len(checkouts) != 1 or checkouts[0].get("with", {}).get("fetch-depth") != 0:
        raise ValueError("Secret scanning requires full Git history")
    if any("gitleaks-action@" in step.get("uses", "") for step in steps) or len(scans) != 1:
        raise ValueError("Secret scanning requires the standalone pinned CLI")
    scan = scans[0]
    script = scan["run"]
    required = ["set -euo pipefail", GITLEAKS_ARCHIVE, GITLEAKS_SHA256, "sha256sum --check --strict", 'tar -xzf "$tool_dir/gitleaks.tar.gz"', '"$tool_dir/gitleaks" git --redact --config .gitleaks.toml --log-opts="--all" .']
    if any(marker not in script for marker in required) or scan.get("shell") != "bash":
        raise ValueError("Secret scanning requires verified Gitleaks 8.30.1, redaction, config and all refs")
    if script.index("sha256sum --check --strict") > script.index("tar -xzf"):
        raise ValueError("Secret scanner checksum must be verified before extraction")
    if job.get("if") or job.get("continue-on-error") or any(step.get("if") or step.get("continue-on-error") for step in steps):
        raise ValueError("Secret scanning cannot be skipped or tolerate failure")


def guarded(jobs, name, seen=None):
    seen = set() if seen is None else seen
    if name in seen:
        return False
    seen.add(name)
    job = jobs[name]
    if job.get("uses") in ["./.github/workflows/quality.yml", "./.github/workflows/web-quality.yml"]:
        return True
    return any(guarded(jobs, parent, set(seen)) for parent in dependencies(job))


def validate(workflows):
    for filename, required in [("quality.yml", REQUIRED), ("web-quality.yml", WEB_REQUIRED)]:
        quality = workflows[filename]
        jobs = quality["jobs"]
        if set(jobs) != required | {"quality-complete"} or set(dependencies(jobs["quality-complete"])) != required:
            raise ValueError("Quality completion must include every required subsystem")
        if "result['result'] != 'success'" not in runs(jobs["quality-complete"]) or "raise SystemExit" not in runs(jobs["quality-complete"]):
            raise ValueError("Skipped, failed or cancelled quality checks cannot pass")
        if (quality.get("on", quality.get(True, {})).get("workflow_call") or {}).get("inputs"):
            raise ValueError("Quality cannot expose bypass inputs")
        for suite in ["rules", "integration", "launch", "messaging", "attendance"]:
            if f"npm run test:{suite}" not in runs(jobs["firebase-emulators"]):
                raise ValueError("Missing emulator gate: " + suite)
        for suite in ["public-browser", "flutter-browser"]:
            if "--suite " + suite not in runs(jobs["browser-journeys"]):
                raise ValueError("Missing browser journey gate: " + suite)
        validate_secret_scan(jobs["secret-scan"])
    for filename, workflow in workflows.items():
        jobs = workflow["jobs"]
        for name, job in jobs.items():
            if any(parent not in jobs for parent in dependencies(job)):
                raise ValueError("Unknown workflow dependency")
            ordered = [step.get("run", "") for step in job.get("steps", [])]
            for command in ordered:
                for line in command.splitlines():
                    if "flutter pub get" in line and "--enforce-lockfile" not in line:
                        raise ValueError("Dependency restore must enforce the application lockfile")
                    if re.search(r"flutter build (?:apk|appbundle)\b", line) and "--no-pub" in line:
                        raise ValueError("Android builds must regenerate the release plugin registry")
            for index, command in enumerate(ordered):
                if "flutter build web" in command:
                    environment = '\"$TARGET_ENV\"' if "ATTENDUS_FIREBASE_ENV=\"$TARGET_ENV\"" in command else "production"
                    later = ordered[index + 1:]
                    configured = False
                    for item in later:
                        if "package_web_release.dart" in item or "flutter build web" in item:
                            break
                        if "configure_web_environment.dart --environment " + environment in item:
                            configured = True
                    if not configured:
                        raise ValueError("Web build lacks environment configuration before packaging")
            if MUTATION.search(str(job.get("steps", []))):
                if filename not in ["firebase-release.yml", "web-release-promote.yml", "native-release.yml"]:
                    raise ValueError("Deployment escaped guarded orchestration")
                if filename != "web-release-promote.yml" and not guarded(jobs, name):
                    raise ValueError("Deployment bypasses same-source quality")
                if "--force" in runs(job):
                    raise ValueError("Broad forced deletion is forbidden")
    candidate = workflows["firebase-release.yml"]
    web_ci = workflows["web-ci.yml"]
    if web_ci["jobs"].get("web-quality", {}).get("uses") != "./.github/workflows/web-quality.yml" or not {"push", "pull_request"} <= set(web_ci["on"]):
        raise ValueError("A dedicated required web quality caller must cover pushes and PRs")
    if set(candidate["on"]) != {"workflow_dispatch"}:
        raise ValueError("Candidate deployment must be explicit")
    jobs = candidate["jobs"]
    if jobs["quality"].get("uses") != "./.github/workflows/web-quality.yml" or len([j for j in jobs.values() if j.get("uses") == "./.github/workflows/web-quality.yml"]) != 1:
        raise ValueError("Candidate must use one same-SHA web quality result")
    if jobs["candidates"]["strategy"]["matrix"]["environment"] != ["staging", "production"] or set(dependencies(jobs["staging"])) != {"quality", "candidates"}:
        raise ValueError("Both frozen environment artifacts precede staging")
    if jobs["staging"].get("environment") != "staging" or "production" in jobs:
        raise ValueError("Candidate cannot promote production")
    for filename, command in [("web-release-qualify.yml", "qualify"), ("web-release-promote.yml", "promote"), ("web-release-observe.yml", None)]:
        workflow = workflows[filename]
        if set(workflow["on"]) != {"workflow_dispatch"}:
            raise ValueError("Qualification and promotion must be explicit")
        for job in workflow["jobs"].values():
            if "flutter build" in runs(job) or "flutter pub get" in runs(job):
                raise ValueError("Qualification and promotion must never rebuild")
        if command and not any("web_release_pipeline.js " + command in runs(job) for job in workflow["jobs"].values()):
            raise ValueError("Missing provenance-verifying release command")
    promotion = workflows["web-release-promote.yml"]["jobs"]["promote"]
    if promotion.get("environment") != "production" or "--expected-prior-release" not in runs(promotion) or "--qualification-run" not in runs(promotion):
        raise ValueError("Production requires protected environment, provenance and predecessor")
    collector = workflows["web-release-observe.yml"]
    collect = collector["jobs"]["collect"]
    if "safari" not in collector["on"]["workflow_dispatch"]["inputs"]["producer"]["options"] or collect.get("runs-on") != "${{ inputs.producer == 'safari' && 'macos-15' || 'ubuntu-latest' }}":
        raise ValueError("Actual Safari evidence requires the pinned macOS runner")
    for step in collect.get("steps", []):
        if "playwright install" in step.get("run", "") and step.get("if") != "${{ inputs.producer != 'safari' }}":
            raise ValueError("Safari must use its native driver instead of Playwright binaries")
    for filename in ["firebase-hosting-merge.yml", "firebase-hosting-pull-request.yml", "deploy-functions.yml", "deploy-firestore-indexes.yml"]:
        if any(job.get("uses") == "./.github/workflows/firebase-release.yml" or MUTATION.search(str(job)) for job in workflows[filename]["jobs"].values()):
            raise ValueError("Legacy entrypoint bypasses qualified promotion")


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflows = load_workflows()

    def mutate(self, callback, expected):
        altered = copy.deepcopy(self.workflows)
        callback(altered)
        with self.assertRaisesRegex(ValueError, expected):
            validate(altered)

    def test_repository_graph(self):
        validate(self.workflows)

    def test_missing_same_source_quality(self):
        self.mutate(lambda w: w["firebase-release.yml"]["jobs"]["staging"].update(needs=[]), "bypasses same-source quality")

    def test_main_push_cannot_promote(self):
        self.mutate(lambda w: w["web-release-promote.yml"].update({"on": {"push": {"branches": ["main"]}}}), "must be explicit")

    def test_promotion_cannot_rebuild(self):
        self.mutate(lambda w: w["web-release-promote.yml"]["jobs"]["promote"]["steps"].append({"run": "flutter build apk --release"}), "must never rebuild")

    def test_production_environment_required(self):
        self.mutate(lambda w: w["web-release-promote.yml"]["jobs"]["promote"].pop("environment"), "protected environment")

    def test_predecessor_required(self):
        def change(w):
            for step in w["web-release-promote.yml"]["jobs"]["promote"]["steps"]:
                if "run" in step:
                    step["run"] = step["run"].replace("--expected-prior-release", "--ignored")
        self.mutate(change, "predecessor")

    def test_safari_requires_actual_macos_runner(self):
        self.mutate(lambda w: w["web-release-observe.yml"]["jobs"]["collect"].update({"runs-on": "ubuntu-latest"}), "Actual Safari")

    def test_launch_and_browser_gates_cannot_be_omitted(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            for job, marker in [("firebase-emulators", "test:launch"), ("browser-journeys", "--suite flutter-browser")]:
                def change(w):
                    steps = w[filename]["jobs"][job]["steps"]
                    steps[:] = [s for s in steps if marker not in s.get("run", "")]
                self.mutate(change, "Missing")

    def test_quality_has_no_skip_input(self):
        self.mutate(lambda w: w["web-quality.yml"]["on"].update(workflow_call={"inputs": {"skip": {"type": "boolean"}}}), "bypass inputs")

    def test_secret_scan_requires_full_history(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            self.mutate(lambda w: w[filename]["jobs"]["secret-scan"]["steps"][0]["with"].update({"fetch-depth": 1}), "full Git history")

    def test_secret_scan_cannot_revert_to_action_or_ignore_failure(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            self.mutate(lambda w: w[filename]["jobs"]["secret-scan"]["steps"].append({"uses": "gitleaks/gitleaks-action@v3"}), "standalone pinned CLI")
            self.mutate(lambda w: w[filename]["jobs"]["secret-scan"].update({"continue-on-error": True}), "cannot be skipped")

    def test_secret_scan_pins_checksum_and_redacts_all_refs(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            for marker in [GITLEAKS_ARCHIVE, GITLEAKS_SHA256, "set -euo pipefail", "--redact", "--config .gitleaks.toml", '--log-opts="--all"']:
                def change(w):
                    step = w[filename]["jobs"]["secret-scan"]["steps"][1]
                    step["run"] = step["run"].replace(marker, "omitted")
                self.mutate(change, "verified Gitleaks")

    def test_secret_scanner_checksum_precedes_extraction(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            def change(w):
                step = w[filename]["jobs"]["secret-scan"]["steps"][1]
                lines = step["run"].splitlines()
                verification = next(line for line in lines if "sha256sum --check --strict" in line)
                lines.remove(verification)
                lines.append(verification)
                step["run"] = "\n".join(lines)
            self.mutate(change, "before extraction")

    def test_environment_configuration_precedes_packaging(self):
        for filename, job in [("quality.yml", "web-release"), ("firebase-release.yml", "candidates")]:
            def change(w):
                steps = w[filename]["jobs"][job]["steps"]
                steps[:] = [s for s in steps if "configure_web_environment.dart" not in s.get("run", "")]
            self.mutate(change, "lacks environment configuration")

    def test_lockfile_and_android_registry_guards(self):
        count = 0
        for filename, workflow in self.workflows.items():
            for name, job in workflow["jobs"].items():
                for index, step in enumerate(job.get("steps", [])):
                    command = step.get("run", "")
                    if "flutter pub get" in command:
                        count += 1
                        def change(w):
                            w[filename]["jobs"][name]["steps"][index]["run"] = command.replace("--enforce-lockfile", "")
                        self.mutate(change, "enforce the application lockfile")
                    if re.search(r"flutter build (?:apk|appbundle)\b", command):
                        def change(w):
                            w[filename]["jobs"][name]["steps"][index]["run"] = command.replace("--release", "--release --no-pub")
                        self.mutate(change, "regenerate the release plugin registry")
        self.assertGreaterEqual(count, 10)

    def test_local_deploy_cannot_enter_build_path(self):
        source = (WORKFLOWS.parent.parent / "scripts/build_web_release.ps1").read_text()
        deploy = source.index("if ($Deploy)")
        build = source.index("if (-not $SkipClean)")
        self.assertLess(deploy, build)
        self.assertIn("web_release_pipeline.js promote", source[deploy:build])
        self.assertIn("return", source[deploy:build])
        self.assertNotIn("firebase deploy", source)


if __name__ == "__main__":
    unittest.main()
