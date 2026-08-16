"use strict";

(() => {
  const configNode = document.getElementById("attendus-public-config");
  if (!configNode) return;
  let config;
  try {
    config = JSON.parse(configNode.textContent || "{}");
  } catch (_) {
    return;
  }
  let firebaseContext;
  let lastTrigger;

  function status(message) {
    const node = document.getElementById("public-action-status");
    if (node) node.textContent = message;
  }

  function idempotencyKey(prefix) {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    return `${prefix}:${Array.from(bytes, (value) => value.toString(16)
        .padStart(2, "0")).join("")}`;
  }

  function dialog(title) {
    const node = document.createElement("dialog");
    node.className = "public-dialog";
    node.setAttribute("aria-labelledby", "public-dialog-title");
    node.innerHTML = `<div class="dialog-inner"><div class="dialog-header"><h2 id="public-dialog-title"></h2><button class="icon-button" type="button" aria-label="Close">×</button></div><div class="dialog-content"></div><p class="dialog-status" role="status" aria-live="polite"></p></div>`;
    node.querySelector("h2").textContent = title;
    const close = () => node.close();
    node.querySelector(".icon-button").addEventListener("click", close);
    node.addEventListener("cancel", (event) => {
      event.preventDefault();
      close();
    });
    node.addEventListener("close", () => {
      node.remove();
      lastTrigger?.focus();
    });
    document.body.append(node);
    node.showModal();
    node.querySelector(".icon-button").focus();
    return node;
  }

  function dialogStatus(node, message, error = false) {
    const output = node.querySelector(".dialog-status");
    output.textContent = message;
    output.style.color = error ? "#a61b1b" : "";
  }

  async function firebase() {
    if (firebaseContext) return firebaseContext;
    if (!config.appCheckSiteKey) {
      throw new Error("Secure registration is not configured.");
    }
    const version = "11.10.0";
    const [appModule, authModule, functionsModule, appCheckModule] =
      await Promise.all([
        import(`https://www.gstatic.com/firebasejs/${version}/firebase-app.js`),
        import(`https://www.gstatic.com/firebasejs/${version}/firebase-auth.js`),
        import(`https://www.gstatic.com/firebasejs/${version}/firebase-functions.js`),
        import(`https://www.gstatic.com/firebasejs/${version}/firebase-app-check.js`),
      ]);
    const app = appModule.initializeApp(config.firebase, "attendus-public-web");
    appCheckModule.initializeAppCheck(app, {
      provider: new appCheckModule.ReCaptchaEnterpriseProvider(config.appCheckSiteKey),
      isTokenAutoRefreshEnabled: true,
    });
    firebaseContext = {
      auth: authModule.getAuth(app),
      functions: functionsModule.getFunctions(app, "us-central1"),
      authModule,
      functionsModule,
    };
    return firebaseContext;
  }

  async function authenticate() {
    const context = await firebase();
    if (context.auth.currentUser && !context.auth.currentUser.isAnonymous) {
      return {context, profile: null};
    }
    const node = dialog("Sign in to continue");
    const content = node.querySelector(".dialog-content");
    content.innerHTML = `<div class="auth-form"><button class="secondary-button google" type="button">Continue with Google</button><p>or use email</p><label>Full name <input name="name" autocomplete="name"></label><label>Email <input name="email" type="email" autocomplete="email" required></label><label>Password <input name="password" type="password" autocomplete="current-password" minlength="8" required></label><button class="cta sign-in" type="button">Sign in</button><button class="secondary-button create" type="button">Create account</button></div>`;
    return new Promise((resolve, reject) => {
      node.addEventListener("close", () => reject(new Error("Sign-in cancelled.")), {once: true});
      content.querySelector(".google").addEventListener("click", async () => {
        dialogStatus(node, "Opening Google sign-in…");
        try {
          const provider = new context.authModule.GoogleAuthProvider();
          await context.authModule.signInWithPopup(context.auth, provider);
          resolve({context, profile: null});
          node.close();
        } catch (error) {
          dialogStatus(node, error.message || "Google sign-in failed.", true);
        }
      });
      const emailAction = async (create) => {
        const email = content.querySelector("[name=email]").value.trim();
        const password = content.querySelector("[name=password]").value;
        const fullName = content.querySelector("[name=name]").value.trim();
        if (!email || password.length < 8 || (create && !fullName)) {
          dialogStatus(node, create ?
            "Enter your name, email, and a password of at least 8 characters." :
            "Enter your email and password.", true);
          return;
        }
        dialogStatus(node, create ? "Creating your account…" : "Signing you in…");
        try {
          if (create) {
            const credential = await context.authModule.createUserWithEmailAndPassword(
                context.auth, email, password,
            );
            await context.authModule.updateProfile(credential.user, {displayName: fullName});
          } else {
            await context.authModule.signInWithEmailAndPassword(context.auth, email, password);
          }
          resolve({context, profile: fullName ? {fullName} : null});
          node.close();
        } catch (error) {
          dialogStatus(node, error.message || "Authentication failed.", true);
        }
      };
      content.querySelector(".sign-in").addEventListener("click", () => emailAction(false));
      content.querySelector(".create").addEventListener("click", () => emailAction(true));
    });
  }

  async function call(name, data, context) {
    const callable = context.functionsModule.httpsCallable(context.functions, name);
    return (await callable(data)).data;
  }

  function loadStripe() {
    if (window.Stripe) return Promise.resolve(window.Stripe);
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "https://js.stripe.com/v3/";
      script.onload = () => resolve(window.Stripe);
      script.onerror = () => reject(new Error("Secure payment could not be loaded."));
      document.head.append(script);
    });
  }

  async function paidCheckout(eventId, auth) {
    if (!config.paidTicketCheckoutEnabled || !config.stripePublishableKey) {
      throw new Error("Paid checkout is temporarily unavailable.");
    }
    const checkout = await call("createPublicTicketCheckoutV1", {
      eventId,
      idempotencyKey: idempotencyKey("checkout"),
      profile: auth.profile,
    }, auth.context);
    const Stripe = await loadStripe();
    const stripe = Stripe(config.stripePublishableKey);
    const elements = stripe.elements({clientSecret: checkout.clientSecret});
    const node = dialog("Complete your ticket purchase");
    const content = node.querySelector(".dialog-content");
    content.innerHTML = `<div id="payment-element"></div><button class="cta pay" type="button">Pay securely</button>`;
    elements.create("payment").mount("#payment-element");
    content.querySelector(".pay").addEventListener("click", async () => {
      dialogStatus(node, "Confirming payment…");
      const result = await stripe.confirmPayment({
        elements,
        confirmParams: {return_url: `${location.origin}/event/${encodeURIComponent(eventId)}?checkout=${encodeURIComponent(checkout.checkoutId)}`},
      });
      if (result.error) dialogStatus(node, result.error.message || "Payment failed.", true);
    });
  }

  async function perform(eventId, action) {
    const auth = await authenticate();
    if (action === "rsvp") {
      const result = await call("registerPublicEventV1", {
        eventId,
        idempotencyKey: idempotencyKey("rsvp"),
        profile: auth.profile,
      }, auth.context);
      status(result.status === "already_registered" ?
        "You are already registered." : "Your RSVP is confirmed.");
      window.alert(result.status === "already_registered" ?
        "You are already registered." : "Your RSVP is confirmed.");
      return;
    }
    if (config.ticketState === "free_ticket") {
      await call("issueFreeTicket", {eventId}, auth.context);
      status("Your ticket is ready.");
      window.alert("Your free ticket is ready in Attendus.");
      return;
    }
    await paidCheckout(eventId, auth);
  }

  for (const trigger of document.querySelectorAll("[data-public-action]")) {
    trigger.addEventListener("click", async (event) => {
      if (!config.inlineRegistrationEnabled) return;
      event.preventDefault();
      lastTrigger = trigger;
      trigger.setAttribute("aria-busy", "true");
      status("Preparing secure registration.");
      try {
        await perform(trigger.dataset.eventId, trigger.dataset.publicAction);
      } catch (error) {
        status(error.message || "Registration could not be completed.");
        window.alert(error.message || "Registration could not be completed.");
      } finally {
        trigger.removeAttribute("aria-busy");
      }
    });
  }
})();
