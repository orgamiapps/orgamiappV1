"use strict";

const runtimeKeys = new Set([
  "PATH", "PATHEXT", "SYSTEMROOT", "WINDIR", "COMSPEC", "SYSTEMDRIVE",
  "TEMP", "TMP", "TMPDIR", "USERPROFILE", "HOME", "HOMEDRIVE", "HOMEPATH",
  "APPDATA", "LOCALAPPDATA", "PROGRAMDATA", "PROGRAMFILES", "PROGRAMFILES(X86)",
  "COMMONPROGRAMFILES", "COMMONPROGRAMFILES(X86)", "JAVA_HOME",
  "ATTENDUS_WEBDRIVER", "CHROME_EXECUTABLE", "ATTENDUS_BROWSER_PROJECT",
  "ATTENDUS_TEST_EDGE", "PYTHON", "PYTHONUTF8", "PYTHONIOENCODING",
  "CI", "GITHUB_ACTIONS", "TERM", "NO_COLOR", "FORCE_COLOR",
]);

function emulatorEnvironment(source) {
  // Firebase CLI debug output can include the complete child environment.
  // Unrelated owner credentials must never enter that process or its workers.
  return Object.fromEntries(Object.entries(source).filter(([key]) => runtimeKeys.has(key.toUpperCase())));
}

function sanitizeEmulatorLog(text) {
  return text.split(/\r?\n/).map((line) => {
    if (/Running .* with environment \{/.test(line)) return "[debug] Emulator child environment omitted from retained diagnostics.";
    return line.replace(/Bearer\s+[^\s"\\]+/gi, "Bearer [redacted]")
        .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[redacted-token]");
  }).join("\n");
}

module.exports = {emulatorEnvironment, sanitizeEmulatorLog};
