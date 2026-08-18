"use strict";

(() => {
  const configNode = document.getElementById("attendus-public-config");
  if (!configNode) return;
  let config;
  try { config = JSON.parse(configNode.textContent || "{}"); } catch (_) { return; }
  let firebaseContext;
  let lastTrigger;

  const status = (message) => {
    const node = document.getElementById("public-action-status");
    if (node) node.textContent = message;
  };
  const idempotencyKey = (prefix) => {
    const bytes = new Uint8Array(16); crypto.getRandomValues(bytes);
    return `${prefix}:${Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("")}`;
  };
  function dialog(title, className = "") {
    const node = document.createElement("dialog");
    node.className = `public-dialog ${className}`;
    node.setAttribute("aria-labelledby", "public-dialog-title");
    node.innerHTML = `<div class="dialog-inner"><div class="dialog-header"><h2 id="public-dialog-title"></h2><button class="icon-button" type="button" aria-label="Close">&times;</button></div><div class="dialog-content"></div><p class="dialog-status" role="status" aria-live="polite"></p></div>`;
    node.querySelector("h2").textContent = title;
    node.querySelector(".icon-button").addEventListener("click", () => node.close());
    node.addEventListener("cancel", (event) => { event.preventDefault(); node.close(); });
    node.addEventListener("close", () => { node.remove(); lastTrigger?.focus(); });
    document.body.append(node); node.showModal(); return node;
  }
  function dialogStatus(node, message, error = false) {
    const output = node.querySelector(".dialog-status");
    output.textContent = message; output.classList.toggle("error", error);
  }
  async function firebase() {
    if (firebaseContext) return firebaseContext;
    if (!config.appCheckSiteKey) throw new Error("Secure registration is not configured.");
    const version = "11.10.0";
    const [appModule, authModule, functionsModule, appCheckModule] = await Promise.all([
      import(`https://www.gstatic.com/firebasejs/${version}/firebase-app.js`),
      import(`https://www.gstatic.com/firebasejs/${version}/firebase-auth.js`),
      import(`https://www.gstatic.com/firebasejs/${version}/firebase-functions.js`),
      import(`https://www.gstatic.com/firebasejs/${version}/firebase-app-check.js`),
    ]);
    const app = appModule.initializeApp(config.firebase, "attendus-public-web");
    appCheckModule.initializeAppCheck(app, {provider:
      new appCheckModule.ReCaptchaEnterpriseProvider(config.appCheckSiteKey),
    isTokenAutoRefreshEnabled: true});
    const auth = authModule.getAuth(app);
    if (!auth.currentUser) await authModule.signInAnonymously(auth);
    firebaseContext = {auth, authModule,
      functions: functionsModule.getFunctions(app, "us-central1"), functionsModule};
    return firebaseContext;
  }
  async function call(name, data, context) {
    return (await context.functionsModule.httpsCallable(context.functions, name)(data)).data;
  }
  function eventSummary() {
    const event = config.event || {};
    const date = event.date ? new Intl.DateTimeFormat("en-US", {dateStyle: "medium",
      timeStyle: "short"}).format(new Date(event.date)) : "";
    return `<section class="checkout-summary" aria-label="Event summary"><strong></strong><span class="summary-date"></span><span class="summary-location"></span></section>`;
  }
  function registrationForm(node, action, context) {
    const content = node.querySelector(".dialog-content");
    const paid = config.ticketState === "paid_ticket";
    content.innerHTML = `${eventSummary()}<form class="registration-form"><label>Full name <input name="fullName" autocomplete="name" maxlength="160" required></label><label>Email address <input name="email" type="email" autocomplete="email" maxlength="254" required></label><div class="checkout-terms"><span>${paid ? `Ticket: $${Number(config.event?.price || 0).toFixed(2)} USD` : action === "rsvp" ? "RSVP · Free" : "Ticket · Free"}</span><small>Event questions are completed separately during event check-in.</small></div><button class="cta continue" type="submit">${paid ? "Continue to payment" : action === "rsvp" ? "Confirm RSVP" : "Get ticket"}</button></form>`;
    content.querySelector(".checkout-summary strong").textContent = config.event?.title || "Event";
    content.querySelector(".summary-date").textContent = config.event?.date ?
      new Intl.DateTimeFormat("en-US", {dateStyle: "medium", timeStyle: "short"})
          .format(new Date(config.event.date)) : "";
    content.querySelector(".summary-location").textContent = config.event?.location || "";
    const user = context.auth.currentUser;
    if (user?.displayName) content.querySelector("[name=fullName]").value = user.displayName;
    if (user?.email) content.querySelector("[name=email]").value = user.email;
    return content.querySelector("form");
  }
  function loadStripe() {
    if (window.Stripe) return Promise.resolve(window.Stripe);
    return new Promise((resolve, reject) => {
      const script = document.createElement("script"); script.src = "https://js.stripe.com/v3/";
      script.onload = () => resolve(window.Stripe);
      script.onerror = () => reject(new Error("Secure payment could not be loaded."));
      document.head.append(script);
    });
  }
  async function payment(node, registration, context) {
    if (!config.paidTicketCheckoutEnabled || !config.stripePublishableKey) {
      throw new Error("Paid checkout is temporarily unavailable.");
    }
    const Stripe = await loadStripe(); const stripe = Stripe(config.stripePublishableKey);
    const elements = stripe.elements({clientSecret: registration.clientSecret});
    const content = node.querySelector(".dialog-content");
    content.innerHTML = `<div class="payment-heading"><strong>Complete payment</strong><span>$${(registration.amount / 100).toFixed(2)} USD</span></div><div id="payment-element"></div><button class="cta pay" type="button">Pay securely</button>`;
    elements.create("payment").mount("#payment-element");
    await new Promise((resolve, reject) => content.querySelector(".pay").addEventListener("click", async () => {
      dialogStatus(node, "Confirming payment…");
      const result = await stripe.confirmPayment({elements, redirect: "if_required",
        confirmParams: {return_url: `${location.origin}/event/${encodeURIComponent(config.eventId || "")}`}});
      if (result.error) { dialogStatus(node, result.error.message || "Payment failed.", true); reject(result.error); }
      else resolve();
    }, {once: true}));
    for (let index = 0; index < 20; index++) {
      const result = await call("getPublicRegistrationStatusV2", {flowId: registration.flowId}, context);
      if (result.status === "confirmed") return result;
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
    throw new Error("Payment is processing. Your confirmation will arrive shortly.");
  }
  async function upgradeAccount(node, context, email, fullName,
      registrationId, claimToken) {
    const area = node.querySelector(".account-upgrade");
    area.hidden = false;
    const accountReady = () => {
      const follow = area.querySelector(".follow-organizer"); follow.hidden = false;
      follow.addEventListener("click", async () => {
        try {
          await call("followPublicEventOrganizerV1", {eventId: config.eventId}, context);
          follow.textContent = "Following organizer"; follow.disabled = true;
        } catch (error) { dialogStatus(node, error.message || "Organizer could not be followed.", true); }
      }, {once: true});
    };
    area.querySelector(".google-upgrade").addEventListener("click", async () => {
      try {
        const provider = new context.authModule.GoogleAuthProvider();
        try {
          await context.authModule.linkWithPopup(context.auth.currentUser, provider);
        } catch (error) {
          if (error.code !== "auth/credential-already-in-use" &&
              error.code !== "auth/email-already-in-use") throw error;
          await context.authModule.signInWithPopup(context.auth, provider);
        }
        if (registrationId) await call("claimPublicRegistrationV1", {registrationId, claimToken}, context);
        dialogStatus(node, "Account created. Your ticket is saved.");
        accountReady();
      } catch (error) { dialogStatus(node, error.message || "Account could not be linked.", true); }
    });
    const form = area.querySelector(".credential-upgrade");
    form.querySelector(".upgrade-contact").textContent = "Create with this email";
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      try {
        const password = form.querySelector("[name=password]").value;
        if (password.length < 8) throw new Error("Use a password of at least 8 characters.");
        const credential = context.authModule.EmailAuthProvider.credential(email, password);
        let linked;
        try {
          linked = await context.authModule.linkWithCredential(context.auth.currentUser, credential);
        } catch (error) {
          if (error.code !== "auth/email-already-in-use" &&
              error.code !== "auth/credential-already-in-use") throw error;
          linked = await context.authModule.signInWithEmailAndPassword(context.auth,
              email, password);
        }
        await context.authModule.updateProfile(linked.user, {displayName: fullName});
        if (registrationId) await call("claimPublicRegistrationV1", {registrationId, claimToken}, context);
        dialogStatus(node, "Account created. Your ticket is saved.");
        accountReady();
      } catch (error) { dialogStatus(node, error.message || "Account could not be created.", true); }
    });
  }
  function showConfirmation(node, result, email, fullName, context) {
    const content = node.querySelector(".dialog-content");
    content.innerHTML = `<div class="confirmation"><div class="success-mark" aria-hidden="true">✓</div><h3>You're confirmed</h3><p>Your ${result.kind === "rsvp" ? "RSVP" : "ticket"} is ready. We’re sending a secure confirmation to your email.</p><p class="delivery-state" role="status">Email delivery: ${result.deliveryStatus === "pending" ? "sending" : result.deliveryStatus || "sending"}</p>${result.ticketId ? `<div class="ticket-reference"><span>Ticket</span><strong>${result.ticketCode || result.ticketId.slice(-10).toUpperCase()}</strong>${result.ticketQrSvg ? `<div class="ticket-qr" role="img" aria-label="QR ticket code ${result.ticketCode}">${result.ticketQrSvg}</div>` : ""}</div>` : ""}<div class="confirmation-actions">${result.manageUrl ? `<a class="secondary-button" href="${result.manageUrl}">View or print ticket</a>` : ""}<button class="secondary-button add-calendar" type="button">Add to calendar</button></div><section class="account-upgrade" hidden><h3>Save your tickets</h3><p>Create an optional account to manage tickets and follow organizers.</p><button class="secondary-button google-upgrade" type="button">Continue with Google</button><form class="credential-upgrade"><label>Password <input name="password" type="password" minlength="8" autocomplete="new-password"></label><button class="secondary-button upgrade-contact" type="submit"></button></form><button class="secondary-button follow-organizer" type="button" hidden>Follow organizer</button></section><button class="link-button show-account" type="button">Create an account (optional)</button></div>`;
    content.querySelector(".add-calendar").addEventListener("click", () => {
      const event = config.event || {}; const start = new Date(event.date);
      const end = new Date(start.getTime() + 2 * 3600000);
      const compact = (date) => date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
      location.href = `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${encodeURIComponent(event.title || "Event")}&dates=${compact(start)}/${compact(end)}&location=${encodeURIComponent(event.location || "")}`;
    });
    content.querySelector(".show-account").addEventListener("click", (event) => {
      event.currentTarget.hidden = true; upgradeAccount(node, context, email,
          fullName, result.registrationId, result.claimToken);
    }, {once: true});
    if (context.auth.currentUser?.isAnonymous === false) {
      content.querySelector(".show-account").hidden = true;
    }
    dialogStatus(node, "Confirmation complete."); status("Registration confirmed.");
  }
  async function perform(eventId, action) {
    const context = await firebase();
    const node = dialog(action === "rsvp" ? "Confirm your RSVP" : "Get your ticket", "registration-dialog");
    const form = registrationForm(node, action, context);
    await new Promise((resolve, reject) => {
      node.addEventListener("close", () => reject(new Error("Registration cancelled.")), {once: true});
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        if (!form.reportValidity()) return;
        const data = new FormData(form);
        const fullName = String(data.get("fullName") || "").trim();
        const email = String(data.get("email") || "").trim();
        form.querySelector("button").disabled = true; dialogStatus(node, "Securing your place…");
        try {
          const result = await call("startPublicRegistrationV2", {eventId, fullName, email,
            idempotencyKey: idempotencyKey("registration")}, context);
          if (result.status === "confirmation_pending") {
            showConfirmation(node, result, email, fullName, context); resolve(); return;
          }
          const completed = result.status === "payment_pending" ?
            {...result, ...await payment(node, result, context)} : result;
          showConfirmation(node, completed, email, fullName, context); resolve();
        } catch (error) {
          form.querySelector("button").disabled = false;
          dialogStatus(node, error.message || "Registration could not be completed.", true);
        }
      });
    });
  }
  for (const trigger of document.querySelectorAll("[data-public-action]")) {
    trigger.addEventListener("click", async (event) => {
      if (!config.inlineRegistrationEnabled || !config.accountlessRegistrationEnabled) return;
      event.preventDefault(); lastTrigger = trigger; config.eventId = trigger.dataset.eventId;
      trigger.setAttribute("aria-busy", "true"); status("Preparing secure registration.");
      try { await perform(trigger.dataset.eventId, trigger.dataset.publicAction); }
      catch (error) { if (error.message !== "Registration cancelled.") status(error.message); }
      finally { trigger.removeAttribute("aria-busy"); }
    });
  }
})();
