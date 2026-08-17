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
    content.innerHTML = `${eventSummary()}<form class="registration-form"><div class="name-grid"><label>First name <input name="firstName" autocomplete="given-name" maxlength="80" required></label><label>Last name <input name="lastName" autocomplete="family-name" maxlength="80" required></label></div><fieldset><legend>Where should we send your confirmation?</legend><div class="segmented"><label><input type="radio" name="contactType" value="email" checked> Email</label><label><input type="radio" name="contactType" value="phone"> Text</label></div></fieldset><label class="contact-label"><span>Email address</span><input name="contact" type="email" autocomplete="email" required></label><p class="sms-consent" hidden>By continuing, you agree to receive transactional texts from Attendus about this registration. Message and data rates may apply. Reply STOP to opt out or HELP for help.</p><div class="checkout-terms"><span>${paid ? `Ticket: $${Number(config.event?.price || 0).toFixed(2)} USD` : action === "rsvp" ? "RSVP · Free" : "Ticket · Free"}</span><small>Event questions are completed separately during event check-in.</small></div><button class="cta continue" type="submit">${paid ? "Continue to payment" : action === "rsvp" ? "Confirm RSVP" : "Get ticket"}</button></form>`;
    content.querySelector(".checkout-summary strong").textContent = config.event?.title || "Event";
    content.querySelector(".summary-date").textContent = config.event?.date ?
      new Intl.DateTimeFormat("en-US", {dateStyle: "medium", timeStyle: "short"})
          .format(new Date(config.event.date)) : "";
    content.querySelector(".summary-location").textContent = config.event?.location || "";
    const contact = content.querySelector("[name=contact]");
    for (const radio of content.querySelectorAll("[name=contactType]")) {
      radio.addEventListener("change", () => {
        const phone = radio.value === "phone" && radio.checked;
        if (!radio.checked) return;
        contact.type = phone ? "tel" : "email";
        contact.autocomplete = phone ? "tel-national" : "email";
        contact.placeholder = phone ? "(555) 555-0123" : "name@example.com";
        content.querySelector(".contact-label span").textContent = phone ? "U.S. mobile number" : "Email address";
        content.querySelector(".sms-consent").hidden = !phone;
      });
    }
    const user = context.auth.currentUser;
    const names = String(user?.displayName || "").trim().split(/\s+/);
    if (names.length > 1) {
      content.querySelector("[name=firstName]").value = names.shift();
      content.querySelector("[name=lastName]").value = names.join(" ");
    }
    if (user?.email) contact.value = user.email;
    if (user?.phoneNumber) {
      const phone = content.querySelector('[name=contactType][value="phone"]');
      phone.checked = true; phone.dispatchEvent(new Event("change")); contact.value = user.phoneNumber;
    }
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
  async function upgradeAccount(node, context, contactType, contactValue, fullName,
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
    form.querySelector(".upgrade-contact").textContent = contactType === "phone" ?
      "Create with this phone" : "Create with this email";
    if (contactType === "phone") {
      form.querySelector("label").hidden = true;
      const recaptcha = document.createElement("div"); recaptcha.id = "phone-recaptcha";
      form.prepend(recaptcha);
    }
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      try {
        if (contactType === "email") {
          const password = form.querySelector("[name=password]").value;
          if (password.length < 8) throw new Error("Use a password of at least 8 characters.");
          const credential = context.authModule.EmailAuthProvider.credential(contactValue, password);
          let linked;
          try {
            linked = await context.authModule.linkWithCredential(context.auth.currentUser, credential);
          } catch (error) {
            if (error.code !== "auth/email-already-in-use" &&
                error.code !== "auth/credential-already-in-use") throw error;
            linked = await context.authModule.signInWithEmailAndPassword(context.auth,
                contactValue, password);
          }
          await context.authModule.updateProfile(linked.user, {displayName: fullName});
          if (registrationId) await call("claimPublicRegistrationV1", {registrationId, claimToken}, context);
          dialogStatus(node, "Account created. Your ticket is saved.");
          accountReady();
        } else {
          dialogStatus(node, "Sending a verification code…");
          const verifier = new context.authModule.RecaptchaVerifier(context.auth, "phone-recaptcha",
              {size: "invisible"});
          const provider = new context.authModule.PhoneAuthProvider(context.auth);
          const verificationId = await provider.verifyPhoneNumber(contactValue, verifier);
          const codeLabel = document.createElement("label");
          codeLabel.className = "phone-code";
          codeLabel.innerHTML = "Verification code <input inputmode=\"numeric\" autocomplete=\"one-time-code\" pattern=\"[0-9]{6}\" maxlength=\"6\" required>";
          const verify = document.createElement("button");
          verify.type = "button"; verify.className = "secondary-button";
          verify.textContent = "Verify phone";
          form.querySelector("[type=submit]").hidden = true;
          form.append(codeLabel, verify);
          const codeInput = codeLabel.querySelector("input"); codeInput.focus();
          const code = await new Promise((resolve) => verify.addEventListener("click", () => {
            if (!codeInput.reportValidity()) return;
            verify.disabled = true; resolve(codeInput.value.trim());
          }, {once: true}));
          const credential = context.authModule.PhoneAuthProvider.credential(verificationId, code.trim());
          let linked;
          try {
            linked = await context.authModule.linkWithCredential(context.auth.currentUser, credential);
          } catch (error) {
            if (error.code !== "auth/credential-already-in-use") throw error;
            linked = await context.authModule.signInWithCredential(context.auth, credential);
          }
          await context.authModule.updateProfile(linked.user, {displayName: fullName});
          if (registrationId) await call("claimPublicRegistrationV1", {registrationId, claimToken}, context);
          dialogStatus(node, "Account created. Your ticket is saved.");
          accountReady();
        }
      } catch (error) { dialogStatus(node, error.message || "Account could not be created.", true); }
    });
  }
  function showConfirmation(node, result, contactType, contactValue, fullName, context) {
    const content = node.querySelector(".dialog-content");
    content.innerHTML = `<div class="confirmation"><div class="success-mark" aria-hidden="true">✓</div><h3>You're confirmed</h3><p>Your ${result.kind === "rsvp" ? "RSVP" : "ticket"} is ready. We’re sending a secure confirmation to your ${contactType === "phone" ? "mobile number" : "email"}.</p>${result.ticketId ? `<div class="ticket-reference"><span>Ticket</span><strong>${result.ticketCode || result.ticketId.slice(-10).toUpperCase()}</strong>${result.ticketQrSvg ? `<div class="ticket-qr" role="img" aria-label="QR ticket code ${result.ticketCode}">${result.ticketQrSvg}</div>` : ""}</div>` : ""}<div class="confirmation-actions">${result.manageUrl ? `<a class="secondary-button" href="${result.manageUrl}">View or print ticket</a>` : ""}<button class="secondary-button add-calendar" type="button">Add to calendar</button></div><section class="account-upgrade" hidden><h3>Save your tickets</h3><p>Create an optional account to manage tickets and follow organizers.</p><button class="secondary-button google-upgrade" type="button">Continue with Google</button><form class="credential-upgrade"><label>Password <input name="password" type="password" minlength="8" autocomplete="new-password"></label><button class="secondary-button upgrade-contact" type="submit"></button></form><button class="secondary-button follow-organizer" type="button" hidden>Follow organizer</button></section><button class="link-button show-account" type="button">Create an account (optional)</button></div>`;
    content.querySelector(".add-calendar").addEventListener("click", () => {
      const event = config.event || {}; const start = new Date(event.date);
      const end = new Date(start.getTime() + 2 * 3600000);
      const compact = (date) => date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
      location.href = `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${encodeURIComponent(event.title || "Event")}&dates=${compact(start)}/${compact(end)}&location=${encodeURIComponent(event.location || "")}`;
    });
    content.querySelector(".show-account").addEventListener("click", (event) => {
      event.currentTarget.hidden = true; upgradeAccount(node, context, contactType, contactValue,
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
        const firstName = String(data.get("firstName") || "").trim();
        const lastName = String(data.get("lastName") || "").trim();
        const contactType = String(data.get("contactType") || "email");
        const contactValue = String(data.get("contact") || "").trim();
        form.querySelector("button").disabled = true; dialogStatus(node, "Securing your place…");
        try {
          const result = await call("startPublicRegistrationV2", {eventId, firstName, lastName,
            contactType, contactValue, idempotencyKey: idempotencyKey("registration")}, context);
          if (result.status === "confirmation_pending") {
            showConfirmation(node, result, contactType, contactValue,
                `${firstName} ${lastName}`, context); resolve(); return;
          }
          const completed = result.status === "payment_pending" ?
            {...result, ...await payment(node, result, context)} : result;
          showConfirmation(node, completed, contactType, contactValue,
              `${firstName} ${lastName}`, context); resolve();
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
