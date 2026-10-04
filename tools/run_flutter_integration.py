"""Run the real Flutter registration journey only against local demo emulators."""
import os
import json
import secrets
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.request
import urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[1]
REQUIRED_FUNCTIONS = [
    'startPublicRegistrationV3', 'getPublicRegistrationStatusV2',
    'getPublicProfilesV1', 'saveEventDraftV1', 'publishEventDraftV1',
    'getEventCapabilitiesV1', 'listEventRosterV2', 'createEventExportV2',
    'previewEventCancellationV1', 'getDiscoveryHomeV1',
]


def callable_ready(status, payload):
    """An emulator socket/404 is not evidence that Functions loaded metadata."""
    if status == 200 and isinstance(payload, dict) and ('result' in payload or 'data' in payload):
        return True
    return status in (400, 401, 403) and isinstance(payload, dict) and payload.get('error', {}).get('status') in (
        'UNAUTHENTICATED', 'INVALID_ARGUMENT', 'PERMISSION_DENIED', 'FAILED_PRECONDITION')


def wait_for_functions(host='127.0.0.1:5101', timeout=90):
    if not re.fullmatch(r'127\.0\.0\.1:\d+', host):
        raise RuntimeError('Functions readiness must target loopback.')
    pending = set(REQUIRED_FUNCTIONS)
    deadline = time.monotonic() + timeout
    errors = {}
    while pending and time.monotonic() < deadline:
        for name in list(pending):
            request = urllib.request.Request(
                f'http://{host}/demo-attendus-admin/us-central1/{name}',
                data=b'{"data":{}}', headers={'content-type': 'application/json'})
            try:
                try:
                    response = urllib.request.urlopen(request, timeout=5)
                except urllib.error.HTTPError as error:
                    response = error
                with response:
                    payload = json.loads(response.read())
                    if callable_ready(response.status, payload):
                        pending.remove(name)
                    else:
                        errors[name] = f'HTTP {response.status}: no loaded callable envelope'
            except (OSError, ValueError) as error:
                errors[name] = str(error)
        if pending:
            time.sleep(0.5)
    if pending:
        raise RuntimeError('Functions did not load required handlers; no browser tests started. '
                           'Inspect emulator metadata/startup errors. ' + json.dumps({name: errors.get(name) for name in sorted(pending)}))
    return sorted(REQUIRED_FUNCTIONS)


def stop(process):
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    else:
        os.killpg(process.pid, signal.SIGTERM)
    process.wait(timeout=20)


def main():
    # Flutter diagnostics contain Unicode even on a Windows cp1252 console.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if os.environ.get("GCLOUD_PROJECT") != "demo-attendus-admin":
        raise RuntimeError("Flutter integration requires demo-attendus-admin.")
    for key in ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]:
        if not re.fullmatch(r"127\.0\.0\.1:\d+", os.environ.get(key, "")):
            raise RuntimeError(f"Missing local emulator: {key}")
    ready_functions = wait_for_functions()
    driver = os.environ.get("ATTENDUS_WEBDRIVER") or shutil.which("chromedriver")
    flutter = shutil.which("flutter")
    if not driver or not flutter:
        raise RuntimeError("Install matching Chrome/ChromeDriver; set ATTENDUS_WEBDRIVER and CHROME_EXECUTABLE.")
    processes = []
    logs = []
    os.environ['ATTENDUS_BROWSER_RUN_ID'] = 'browser-' + secrets.token_hex(8)
    os.environ['ATTENDUS_FIXTURE_TOKEN'] = secrets.token_hex(32)
    evidence = ROOT / "build" / "debugging-flutter-integration" / os.environ['ATTENDUS_BROWSER_RUN_ID']
    evidence.mkdir(parents=True, exist_ok=False)
    os.environ['ATTENDUS_BROWSER_EVIDENCE'] = str(evidence)
    (evidence / 'readiness.json').write_text(json.dumps({'project': 'demo-attendus-admin', 'handlers': ready_functions}), encoding='utf-8')
    try:
        for command in [[shutil.which("node"), str(ROOT / "tests/browser/server.cjs")],
                        [driver, "--port=4445", "--allowed-ips=127.0.0.1"],
                        [shutil.which("node"), str(ROOT / "tests/browser/webdriver-proxy.cjs")]]:
            output = (evidence / f"service-{len(processes)}.log").open("w", encoding="utf-8")
            logs.append(output)
            processes.append(subprocess.Popen(command, cwd=ROOT, start_new_session=os.name != "nt",
                                              stdout=output, stderr=subprocess.STDOUT,
                                              creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0))
        for url in ["http://127.0.0.1:4173/__health", "http://127.0.0.1:4444/status"]:
            deadline = time.monotonic() + 30
            while True:
                try:
                    with urllib.request.urlopen(url, timeout=2) as response:
                        if response.status == 200:
                            break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f"Local test service did not start: {url}")
                    time.sleep(0.2)
        command = [flutter, "drive", "--driver=test_driver/integration_test.dart",
                   "--target=integration_test/all_web_journeys_test.dart", "-d", "web-server",
                   "--browser-name=chrome", "--headless", "--driver-port=4444",
                   "--dart-define=ATTENDUS_FIREBASE_ENV=emulator",
                   f"--dart-define=ATTENDUS_BROWSER_RUN_ID={os.environ['ATTENDUS_BROWSER_RUN_ID']}",
                   f"--dart-define=ATTENDUS_FIXTURE_TOKEN={os.environ['ATTENDUS_FIXTURE_TOKEN']}"]
        # WebDriver does not use Flutter's CHROME_EXECUTABLE environment variable.
        if os.environ.get("CHROME_EXECUTABLE"):
            chrome = pathlib.Path(os.environ["CHROME_EXECUTABLE"])
            if not chrome.is_file():
                raise RuntimeError("CHROME_EXECUTABLE does not identify a browser binary.")
            command.append(f"--chrome-binary={chrome}")
        flutter_log = evidence / "flutter-drive.log"
        output = flutter_log.open("w", encoding="utf-8")
        logs.append(output)
        print(f"Flutter journey output: {flutter_log}", flush=True)
        process = subprocess.Popen(command, cwd=ROOT, start_new_session=os.name != "nt",
                                   stdout=output, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        processes.append(process)
        result = process.wait(timeout=1800)
        output.flush()
        print(flutter_log.read_text(encoding="utf-8", errors="replace")[-20000:], flush=True)
    finally:
        cleanup_error = None
        try:
            request = urllib.request.Request('http://127.0.0.1:4173/__cleanup', method='POST', data=b'{}',
                headers={'content-type': 'application/json', 'x-fixture-token': os.environ['ATTENDUS_FIXTURE_TOKEN']})
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
                (evidence / 'cleanup.json').write_bytes(payload)
                if json.loads(payload).get('complete') is not True:
                    raise RuntimeError('Fixture cleanup did not complete.')
        except (OSError, ValueError, RuntimeError) as error:
            cleanup_error = error
            (evidence / 'cleanup-error.txt').write_text(str(error), encoding='utf-8')
        for process in reversed(processes):
            stop(process)
        for output in logs:
            output.close()
        if cleanup_error is not None:
            raise RuntimeError('Fixture cleanup failed; preserve this run for recovery.') from cleanup_error
    return result


if __name__ == "__main__":
    raise SystemExit(main())
