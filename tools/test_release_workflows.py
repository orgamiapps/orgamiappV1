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
    required = ["set -euo pipefail", GITLEAKS_ARCHIVE, GITLEAKS_SHA256, "sha256sum --check --strict", 'tar -xzf "$tool_dir/gitleaks.tar.gz"', 'node tools/test_gitleaks_allowlists.js "$tool_dir/gitleaks"', '"$tool_dir/gitleaks" git --redact --config .gitleaks.toml --log-opts="--all" .']
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


def validate_appcheck_diagnostics(workflows):
    collector = workflows["web-release-observe.yml"]
    collect = collector["jobs"]["collect"]
    mode = collector["on"]["workflow_dispatch"]["inputs"].get("app_check_mode", {})
    if mode.get("type") != "choice" or mode.get("options") != ["real", "staging-debug-functional"] or mode.get("default") != "real" or mode.get("required") is not True:
        raise ValueError("App Check diagnostics require an explicit choice with real default")
    if collect.get("environment") != "staging" or collect.get("env", {}).get("APPCHECK_MODE") != "${{ inputs.app_check_mode }}":
        raise ValueError("App Check diagnostics require the staging environment and explicit mode binding")
    steps = collect.get("steps", [])
    guard = "collectionAppCheckMode(process.env.PRODUCER, process.env.GATES, process.env.APPCHECK_MODE)"
    guards = [index for index, step in enumerate(steps) if guard in step.get("run", "")]
    protected = [index for index, step in enumerate(steps) if step.get("uses", "").startswith(("google-github-actions/auth@", "actions/setup-node@")) or "npm ci" in step.get("run", "")]
    if len(guards) != 1 or not protected or guards[0] >= min(protected) or steps[guards[0]].get("if"):
        raise ValueError("App Check browser-only preflight must precede installation and authentication")
    command = "node tools/web_release_evidence.js"
    execution = [step for step in steps if command in step.get("run", "")]
    diagnostic = [step for step in execution if "--app-check-mode staging-debug-functional" in step["run"]]
    real = [step for step in execution if "--app-check-mode" not in step["run"]]
    if len(execution) != 2 or len(diagnostic) != 1 or len(real) != 1 or diagnostic[0].get("if") != "${{ inputs.app_check_mode == 'staging-debug-functional' }}" or real[0].get("if") != "${{ inputs.app_check_mode == 'real' }}":
        raise ValueError("Real and debug execution must have exclusive explicit mode conditions")
    secrets = {"STAGING_APPCHECK_DEBUG_TOKEN": "${{ secrets.STAGING_APPCHECK_DEBUG_TOKEN }}",
               "STAGING_APPCHECK_DEBUG_RESOURCE": "${{ vars.STAGING_APPCHECK_DEBUG_RESOURCE }}"}
    if diagnostic[0].get("env") != secrets:
        raise ValueError("Debug credential and resource must be scoped to the diagnostic execution step")
    # Search every workflow, including build/real jobs. Only the exact diagnostic
    # step's environment mapping may reference these settings, never shell text.
    def contains_debug(value):
        return any(name in str(value) for name in secrets)
    for filename, workflow in workflows.items():
        if contains_debug({key: value for key, value in workflow.items() if key != "jobs"}):
            raise ValueError("Debug settings escaped the diagnostic execution step")
        for name, job in workflow["jobs"].items():
            if contains_debug({key: value for key, value in job.items() if key != "steps"}):
                raise ValueError("Debug settings escaped the diagnostic execution step")
            for step in job.get("steps", []):
                allowed = filename == "web-release-observe.yml" and name == "collect" and step is diagnostic[0]
                scanned = {key: value for key, value in step.items() if key != "env"} if allowed else step
                if contains_debug(scanned):
                    raise ValueError("Debug settings escaped the diagnostic execution step")
    ignored_failure = re.compile(r"\|\|\s*(?:true\b|:\s*(?:$|;)|exit\s+0\b)|\bset\s+\+e\b|\bexit\s+0\b")
    if collect.get("continue-on-error") or any(step.get("continue-on-error") or ignored_failure.search(step.get("run", "")) for step in steps):
        raise ValueError("Diagnostic failure must remain a failed workflow, never continue-on-error")
    if any("web_release_pipeline.js qualify" in step.get("run", "") or "web_release_pipeline.js promote" in step.get("run", "") or step.get("uses") in ["./.github/workflows/web-release-qualify.yml", "./.github/workflows/web-release-promote.yml"] for step in steps):
        raise ValueError("Diagnostic collection cannot invoke qualification or promotion")


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
        function_steps = jobs["functions"]["steps"]
        producer_tests = next((index for index, step in enumerate(function_steps) if "../tests/browser/*.test.cjs" in step.get("run", "")), None)
        if producer_tests is None or not any(step.get("run") == "npm ci" and step.get("working-directory") == "tests/browser" for step in function_steps[:producer_tests]):
            raise ValueError("Producer contracts require locked browser dependencies before execution")
        if "../tools/bridge_web_assets.test.js" not in runs(jobs["functions"]):
            raise ValueError("Immutable Hosting bridge contracts must run before qualification")
        if "../tools/deploy_web_functions.test.js" not in runs(jobs["functions"]):
            raise ValueError("Scoped Functions deployment guard tests must run before qualification")
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
    read_permissions = {"contents": "read", "actions": "read"}
    if candidate.get("permissions") != read_permissions:
        raise ValueError("Candidate workflow permissions must be read-only without shared OIDC")
    for name, job in jobs.items():
        authenticates = any(step.get("uses", "").startswith("google-github-actions/auth@") for step in job.get("steps", []))
        permissions = job.get("permissions", candidate["permissions"])
        if name in {"predecessors", "staging"}:
            if not authenticates or permissions != {**read_permissions, "id-token": "write"}:
                raise ValueError("Only authenticating predecessor/staging jobs may receive job-level OIDC")
        elif authenticates or permissions != read_permissions:
            raise ValueError("Candidate build and quality jobs cannot receive OIDC or cloud authentication")
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
    if not any(step.get("uses", "").startswith("actions/upload-artifact@") and step.get("if") == "always()" and "hosting-asset-bridge.json" in step.get("with", {}).get("path", "") for step in promotion.get("steps", [])):
        raise ValueError("Failed or successful Hosting bridge receipts must be retained")
    for plan_receipt in ["function-deployment-plan.json", "function-preflight-plan.json"]:
        if not any(step.get("uses", "").startswith("actions/upload-artifact@") and step.get("if") == "always()" and plan_receipt in step.get("with", {}).get("path", "") for step in promotion.get("steps", [])):
            raise ValueError("Scoped Functions deployment plan receipts must be retained")
    collector = workflows["web-release-observe.yml"]
    collect = collector["jobs"]["collect"]
    if "post-close-replay" not in collector["on"]["workflow_dispatch"]["inputs"]["gates"]["options"]:
        raise ValueError("The collector must expose the isolated post-close replay mode")
    collector_steps = collect.get("steps", [])
    mode_check = next((index for index, step in enumerate(collector_steps) if "selectedGates(process.env.PRODUCER, process.env.GATES)" in step.get("run", "")), None)
    authentication = next(index for index, step in enumerate(collector_steps) if step.get("uses", "").startswith("google-github-actions/auth@"))
    if mode_check is None or mode_check >= authentication:
        raise ValueError("Producer/mode guard must precede cloud authentication")
    validate_appcheck_diagnostics(workflows)
    if "safari" not in collector["on"]["workflow_dispatch"]["inputs"]["producer"]["options"] or collect.get("runs-on") != "${{ inputs.producer == 'safari' && 'macos-15' || 'ubuntu-latest' }}":
        raise ValueError("Actual Safari evidence requires the pinned macOS runner")
    for step in collect.get("steps", []):
        if "playwright install" in step.get("run", "") and step.get("if") != "${{ inputs.producer == 'browser' }}":
            raise ValueError("Only the browser producer may install Playwright browsers; observations and Safari must skip them")
    installs = [step.get("run", "").split() for step in collect.get("steps", []) if "playwright install" in step.get("run", "")]
    if not any({"chromium", "firefox", "webkit", "chrome", "msedge"}.issubset(command) for command in installs):
        raise ValueError("Browser qualification must install every required engine including branded Chrome and Edge")
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

    def test_observation_jobs_skip_unused_browser_installation(self):
        for condition in [None, "${{ inputs.producer != 'safari' }}", "${{ inputs.producer == 'backend' }}", "${{ inputs.producer == 'operations' }}"]:
            def change(w):
                for step in w["web-release-observe.yml"]["jobs"]["collect"]["steps"]:
                    if "playwright install" in step.get("run", ""):
                        step["if"] = condition
            self.mutate(change, "Only the browser producer")

    def test_browser_collector_installs_required_branded_engines(self):
        for engine in ["chrome", "msedge"]:
            def remove(w):
                for step in w["web-release-observe.yml"]["jobs"]["collect"]["steps"]:
                    if "playwright install" in step.get("run", ""):
                        step["run"] = " ".join(value for value in step["run"].split() if value != engine)
            self.mutate(remove, "branded Chrome and Edge")

    def test_replay_mode_requires_pre_authentication_guard(self):
        def remove(w):
            steps = w["web-release-observe.yml"]["jobs"]["collect"]["steps"]
            steps[:] = [step for step in steps if "selectedGates(" not in step.get("run", "")]
        self.mutate(remove, "guard must precede")

    def test_appcheck_diagnostics_are_explicit_and_real_by_default(self):
        for patch in [{"default": "staging-debug-functional"}, {"required": False}, {"type": "string"}, {"options": ["real", "staging-debug-functional", "skip"]}]:
            self.mutate(lambda w: w["web-release-observe.yml"]["on"]["workflow_dispatch"]["inputs"]["app_check_mode"].update(patch), "explicit choice with real default")
        self.mutate(lambda w: w["web-release-observe.yml"]["jobs"]["collect"]["env"].update(APPCHECK_MODE="real"), "explicit mode binding")

    def test_appcheck_browser_only_preflight_cannot_be_skipped_or_delayed(self):
        for action in ["remove", "after-install", "conditional"]:
            def change(w):
                steps = w["web-release-observe.yml"]["jobs"]["collect"]["steps"]
                guard = next(step for step in steps if "collectionAppCheckMode(" in step.get("run", ""))
                if action == "remove":
                    guard["run"] = guard["run"].replace("e.collectionAppCheckMode(process.env.PRODUCER, process.env.GATES, process.env.APPCHECK_MODE)", "void 0")
                elif action == "conditional":
                    guard["if"] = "${{ inputs.producer == 'browser' }}"
                else:
                    steps.remove(guard)
                    install = next(index for index, step in enumerate(steps) if step.get("uses", "").startswith("actions/setup-node@"))
                    steps.insert(install + 1, guard)
            self.mutate(change, "browser-only preflight")

    def test_appcheck_credentials_do_not_escape_to_job_build_or_real_steps(self):
        for key in ["STAGING_APPCHECK_DEBUG_TOKEN", "STAGING_APPCHECK_DEBUG_RESOURCE"]:
            for location in ["workflow", "job", "build", "real", "diagnostic-command"]:
                def change(w):
                    collect = w["web-release-observe.yml"]["jobs"]["collect"]
                    diagnostic = next(step for step in collect["steps"] if "--app-check-mode staging-debug-functional" in step.get("run", ""))
                    value = diagnostic["env"][key]
                    if location == "workflow":
                        w["web-release-observe.yml"].setdefault("env", {})[key] = value
                    elif location == "job":
                        collect["env"][key] = value
                    elif location == "build":
                        w["firebase-release.yml"]["jobs"]["candidates"].setdefault("env", {})[key] = value
                    elif location == "diagnostic-command":
                        diagnostic["run"] += "\necho $" + key
                    else:
                        real = next(step for step in collect["steps"] if "node tools/web_release_evidence.js" in step.get("run", "") and "--app-check-mode" not in step["run"])
                        real.setdefault("env", {})[key] = value
                self.mutate(change, "escaped the diagnostic execution")

    def test_appcheck_execution_modes_and_secret_mapping_are_not_interchangeable(self):
        for kind in ["real", "diagnostic"]:
            for condition in [None, "always()", "${{ inputs.producer == 'browser' }}"]:
                def change(w):
                    steps = w["web-release-observe.yml"]["jobs"]["collect"]["steps"]
                    step = next(step for step in steps if "node tools/web_release_evidence.js" in step.get("run", "") and ("--app-check-mode" in step["run"]) == (kind == "diagnostic"))
                    step["if"] = condition
                self.mutate(change, "exclusive explicit mode")
        def remove_resource(w):
            steps = w["web-release-observe.yml"]["jobs"]["collect"]["steps"]
            next(step for step in steps if "--app-check-mode staging-debug-functional" in step.get("run", ""))["env"].pop("STAGING_APPCHECK_DEBUG_RESOURCE")
        self.mutate(remove_resource, "scoped to the diagnostic execution")

    def test_appcheck_diagnostic_failures_cannot_be_made_green(self):
        self.mutate(lambda w: w["web-release-observe.yml"]["jobs"]["collect"].update({"continue-on-error": True}), "failed workflow")
        for suffix in ["continue", " || true", " || exit 0", "\nset +e", "\nexit 0"]:
            def change(w):
                steps = w["web-release-observe.yml"]["jobs"]["collect"]["steps"]
                step = next(step for step in steps if "--app-check-mode staging-debug-functional" in step.get("run", ""))
                if suffix == "continue":
                    step["continue-on-error"] = True
                else:
                    step["run"] += suffix
            self.mutate(change, "failed workflow")
        self.mutate(lambda w: w["web-release-observe.yml"]["jobs"]["collect"]["steps"].append({"run": "node tools/web_release_pipeline.js qualify"}), "cannot invoke qualification")

    def test_launch_and_browser_gates_cannot_be_omitted(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            for job, marker in [("firebase-emulators", "test:launch"), ("browser-journeys", "--suite flutter-browser")]:
                def change(w):
                    steps = w[filename]["jobs"][job]["steps"]
                    steps[:] = [s for s in steps if marker not in s.get("run", "")]
                self.mutate(change, "Missing")

    def test_quality_has_no_skip_input(self):
        self.mutate(lambda w: w["web-quality.yml"]["on"].update(workflow_call={"inputs": {"skip": {"type": "boolean"}}}), "bypass inputs")

    def test_candidate_oidc_is_scoped_to_actual_authentication_jobs(self):
        self.mutate(lambda w: w["firebase-release.yml"]["permissions"].update({"id-token": "write"}), "without shared OIDC")
        for name in ["candidates", "quality"]:
            self.mutate(lambda w: w["firebase-release.yml"]["jobs"][name].update(permissions={"contents": "read", "actions": "read", "id-token": "write"}), "cannot receive OIDC")
        for name in ["predecessors", "staging"]:
            self.mutate(lambda w: w["firebase-release.yml"]["jobs"][name].pop("permissions"), "job-level OIDC")
            def remove_authentication(w):
                steps = w["firebase-release.yml"]["jobs"][name]["steps"]
                steps[:] = [step for step in steps if not step.get("uses", "").startswith("google-github-actions/auth@")]
            self.mutate(remove_authentication, "authenticating predecessor/staging")
        self.mutate(lambda w: w["firebase-release.yml"]["jobs"]["candidates"]["steps"].append({"uses": "google-github-actions/auth@v2"}), "cloud authentication")

    def test_hosting_bridge_contracts_and_partial_receipts_are_retained(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            def remove(w):
                for step in w[filename]["jobs"]["functions"]["steps"]:
                    if "run" in step:
                        step["run"] = step["run"].replace("../tools/bridge_web_assets.test.js", "")
            self.mutate(remove, "Hosting bridge contracts")
        def remove_receipt(w):
            for step in w["web-release-promote.yml"]["jobs"]["promote"]["steps"]:
                if step.get("uses", "").startswith("actions/upload-artifact@"):
                    step["with"]["path"] = step["with"]["path"].replace("build/web-promotion/hosting-asset-bridge.json", "")
        self.mutate(remove_receipt, "bridge receipts")

    def test_scoped_function_deployment_checks_and_receipts_are_required(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            def remove(w):
                for step in w[filename]["jobs"]["functions"]["steps"]:
                    if "run" in step:
                        step["run"] = step["run"].replace("../tools/deploy_web_functions.test.js", "")
            self.mutate(remove, "Scoped Functions deployment guard")

        for receipt in ["function-deployment-plan.json", "function-preflight-plan.json"]:
            def remove_receipt(w):
                for step in w["web-release-promote.yml"]["jobs"]["promote"]["steps"]:
                    if step.get("uses", "").startswith("actions/upload-artifact@"):
                        step["with"]["path"] = step["with"]["path"].replace("build/web-promotion/" + receipt, "")
            self.mutate(remove_receipt, "Scoped Functions deployment plan receipts")

    def test_browser_producer_dependencies_precede_contract_tests(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            def remove(w):
                steps = w[filename]["jobs"]["functions"]["steps"]
                steps[:] = [step for step in steps if step.get("working-directory") != "tests/browser"]
            self.mutate(remove, "locked browser dependencies")

            def reorder(w):
                steps = w[filename]["jobs"]["functions"]["steps"]
                restore = next(step for step in steps if step.get("working-directory") == "tests/browser")
                steps.remove(restore)
                steps.append(restore)
            self.mutate(reorder, "locked browser dependencies")

    def test_secret_scan_requires_full_history(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            self.mutate(lambda w: w[filename]["jobs"]["secret-scan"]["steps"][0]["with"].update({"fetch-depth": 1}), "full Git history")

    def test_secret_scan_cannot_revert_to_action_or_ignore_failure(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            self.mutate(lambda w: w[filename]["jobs"]["secret-scan"]["steps"].append({"uses": "gitleaks/gitleaks-action@v3"}), "standalone pinned CLI")
            self.mutate(lambda w: w[filename]["jobs"]["secret-scan"].update({"continue-on-error": True}), "cannot be skipped")

    def test_secret_scan_pins_checksum_and_redacts_all_refs(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            for marker in [GITLEAKS_ARCHIVE, GITLEAKS_SHA256, "set -euo pipefail", "--redact", "--config .gitleaks.toml", '--log-opts="--all"', 'node tools/test_gitleaks_allowlists.js "$tool_dir/gitleaks"']:
                def change(w):
                    step = next(s for s in w[filename]["jobs"]["secret-scan"]["steps"] if '"$tool_dir/gitleaks" git ' in s.get("run", ""))
                    step["run"] = step["run"].replace(marker, "omitted")
                self.mutate(change, "verified Gitleaks")

    def test_secret_scanner_checksum_precedes_extraction(self):
        for filename in ["quality.yml", "web-quality.yml"]:
            def change(w):
                step = next(s for s in w[filename]["jobs"]["secret-scan"]["steps"] if '"$tool_dir/gitleaks" git ' in s.get("run", ""))
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
