"use strict";

// This function is serialized by both Playwright and Safari WebDriver. Keep it
// self-contained: no module constants, closures or arbitrary selector input.
function flutterSemanticsDom(action = "inspect") {
  if (!["inspect", "activate-desktop", "mobile-element"].includes(action)) throw Error("flutter-semantics-invalid-action");
  if (document.querySelectorAll("flt-semantics").length) return {kind: "enabled"};
  const nodes = [...document.querySelectorAll("flt-semantics-placeholder")];
  if (!nodes.length) return {kind: "waiting"};
  if (nodes.length !== 1) throw Error("flutter-semantics-ambiguous-placeholder");
  const node = nodes[0], rect = node.getBoundingClientRect(), style = getComputedStyle(node);
  if (node.tagName.toLowerCase() !== "flt-semantics-placeholder" || node.getAttribute("role") !== "button" ||
      node.getAttribute("aria-label") !== "Enable accessibility") throw Error("flutter-semantics-unexpected-placeholder");
  if (style.display === "none" || style.visibility === "hidden" || rect.width <= 0 || rect.height <= 0) return {kind: "waiting"};
  const close = (actual, expected) => Math.abs(actual - expected) <= 0.1;
  // Pinned Flutter's DesktopSemanticsEnabler intentionally positions its AT
  // activation control outside the viewport. A WebDriver pointer cannot reach
  // it. Its own click listener enables the real engine semantics tree.
  const desktop = close(rect.x, -1) && close(rect.y, -1) && close(rect.width, 1) && close(rect.height, 1);
  const mobile = close(rect.x, 0) && close(rect.y, 0) && close(rect.width, innerWidth) && close(rect.height, innerHeight);
  if (!desktop && !mobile) throw Error("flutter-semantics-unrecognized-placeholder-geometry");
  if (action === "activate-desktop") {
    if (!desktop) throw Error("flutter-semantics-desktop-activation-requires-offscreen-control");
    node.click();
    return {kind: "desktop-activation-dispatched"};
  }
  if (action === "mobile-element") {
    if (!mobile) throw Error("flutter-semantics-pointer-activation-requires-onscreen-control");
    return node;
  }
  return {kind: desktop ? "desktop-placeholder" : "mobile-placeholder",
    rectangle: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}};
}

async function ensureFlutterSemantics(transport, {timeoutMs = 90000, pollMs = 100,
  now = Date.now, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))} = {}) {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0 || timeoutMs > 90000 || !Number.isFinite(pollMs) || pollMs <= 0) throw Error("flutter-semantics-invalid-deadline");
  const startedAt = now(), deadline = startedAt + timeoutMs;
  let activation = null;
  async function bounded(operation) {
    const remaining = deadline - now();
    if (remaining <= 0) throw Error("flutter-semantics-startup-timeout");
    let timer;
    try {
      return await Promise.race([Promise.resolve().then(operation), new Promise((_, reject) => {
        timer = setTimeout(() => reject(Error("flutter-semantics-startup-timeout")), remaining);
      })]);
    } finally {clearTimeout(timer);}
  }
  while (now() < deadline) {
    const observed = await bounded(transport.inspect);
    if (observed?.kind === "enabled") return {activation: activation || "already-enabled", elapsedMs: now() - startedAt};
    if (!activation && observed?.kind === "desktop-placeholder") {
      await bounded(transport.activateDesktop); activation = "desktop-at-click";
    } else if (!activation && observed?.kind === "mobile-placeholder") {
      await bounded(transport.activatePointer); activation = "mobile-pointer-click";
    } else if (!["waiting", "desktop-placeholder", "mobile-placeholder"].includes(observed?.kind)) {
      throw Error("flutter-semantics-invalid-observation");
    }
    await sleep(Math.min(pollMs, Math.max(0, deadline - now())));
  }
  throw Error("flutter-semantics-startup-timeout");
}

function activateFlutterSemanticsPage(page, options) {
  return ensureFlutterSemantics({
    inspect: () => page.evaluate(flutterSemanticsDom, "inspect"),
    activateDesktop: () => page.evaluate(flutterSemanticsDom, "activate-desktop"),
    // The mobile engine requires a real center pointer event for its coordinate
    // disambiguation. No force click, style change or fabricated semantics node.
    activatePointer: () => page.locator("flt-semantics-placeholder").click(),
  }, options);
}

function activateFlutterSemanticsDriver(driver, options) {
  return ensureFlutterSemantics({
    inspect: () => driver.execute(flutterSemanticsDom, "inspect"),
    activateDesktop: () => driver.execute(flutterSemanticsDom, "activate-desktop"),
    activatePointer: async () => {
      const element = await driver.execute(flutterSemanticsDom, "mobile-element");
      if (element?.kind === "enabled") return;
      await driver.click(element);
    },
  }, options);
}

module.exports = {flutterSemanticsDom, ensureFlutterSemantics, activateFlutterSemanticsPage, activateFlutterSemanticsDriver};
