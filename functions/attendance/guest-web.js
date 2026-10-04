"use strict";

const crypto = require("node:crypto");
const {onRequest} = require("firebase-functions/v2/https");
const core = require("./arrival-core");
const arrival = require("./arrival");
const {escapeHtml} = require("../public-web/renderer");

async function guestContext(db, req) {
  const cookies = Object.fromEntries(String(req.get("cookie") || "").split(";")
      .map((part) => part.trim().split("=")).filter((part) => part.length === 2));
  const raw = cookies.attendus_guest_manage;
  if (!raw || raw.length > 512) core.fail("Open your registration management link again.", "unauthenticated");
  const session = (await db.collection("GuestManageSessions").doc(core.digest(raw)).get()).data();
  if (!session || session.status !== "active" || core.millis(session.expiresAt) <= Date.now()) core.fail("Your registration session expired. Open its management link again.", "unauthenticated");
  const reg = await db.collection("RegisterAttendance").doc(session.registrationId).get();
  if (!reg.exists || reg.data().guestId !== session.guestId || !core.confirmedRegistration(reg.data())) core.fail("A confirmed registration is required.", "permission-denied");
  return {session, reg, uid: reg.data().customerUid, eventId: reg.data().eventId};
}

// Serialized into the nonce-protected guest page. Stop the native location
// subscription on success, timeout, permission failure, or leaving foreground.
/* global window, navigator, document */
function acquireGuestLocation() {
  return new Promise((resolve, reject) => {
    if (!window.isSecureContext || !navigator.geolocation) return reject(Error("Location requires a supported HTTPS browser."));
    if (document.hidden) return reject(Error("Keep this page open to confirm your arrival."));
    let watch;
    let timer;
    let finished = false;
    const stop = () => {
      if (watch !== undefined) navigator.geolocation.clearWatch(watch);
      clearTimeout(timer);
      window.removeEventListener("pagehide", leave);
      document.removeEventListener("visibilitychange", visibility);
    };
    const finish = (error, value) => {
      if (finished) return;
      finished = true;
      stop();
      if (error) reject(error); else resolve(value);
    };
    const leave = () => finish(Error("Location stopped when you left the page. Retry when you are ready."));
    const visibility = () => { if (document.hidden) leave(); };
    window.addEventListener("pagehide", leave);
    document.addEventListener("visibilitychange", visibility);
    timer = setTimeout(() => finish(Error("We could not get an accurate location within 10 seconds.")), 10000);
    try {
      watch = navigator.geolocation.watchPosition(position => {
      const age = Date.now() - position.timestamp;
      if (age < -5000 || age > 30000 || !Number.isFinite(position.coords.accuracy) || position.coords.accuracy < 0 || position.coords.accuracy > 50) return;
      finish(null, position);
    }, () => finish(Error("Location is unavailable or permission was declined.")),
    {enableHighAccuracy: true, maximumAge: 0, timeout: 10000});
    } catch (_) { finish(Error("Location is unavailable. Please retry or ask staff.")); }
    if (finished && watch !== undefined) navigator.geolocation.clearWatch(watch);
  });
}

async function guestPassResponse(pass) {
  // This browser cannot satisfy native device authentication. Do not return
  // the underlying credential in JSON when suppressing its visual QR.
  const {qrData, ...metadata} = pass;
  return {...metadata, qrImage: pass.passLockRequired ? null : await require("qrcode").toDataURL(qrData)};
}

function createGuestAttendanceWeb(admin) {
  const db = admin.firestore();
  return onRequest({region: "us-central1", maxInstances: 20,
    secrets: [arrival.SIGNING_KEY]}, async (req, res) => {
    res.set("Cache-Control", "private, no-store");
    res.set("X-Robots-Tag", "noindex, nofollow");
    res.set("Referrer-Policy", "no-referrer");
    const nonce = crypto.randomBytes(18).toString("base64");
    res.set("Content-Security-Policy", `default-src 'self'; script-src 'nonce-${nonce}'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`);
    try {
      const ctx = await guestContext(db, req);
      const event = await arrival.readEvent(db, db, ctx.eventId);
      if (req.method === "POST") {
        if (req.body?.csrf !== ctx.session.csrfToken) return res.sendStatus(403);
        await require("./v2").enforceRateLimit(db, ctx.uid, "guest_attendance_web");
        if (req.body.action === "wallet") {
          const record = await arrival.issuePass(db, ctx.uid, {kind: "event", eventId: ctx.eventId, registrationId: ctx.reg.id, ticketId: req.body.ticketId});
          const pass = await arrival.passResponse(db, record);
          return res.json(await guestPassResponse(pass));
        }
        if (req.body.action === "arrival") {
          // The identity is obtained only from the authenticated management
          // session, never from a browser-supplied UID or email address.
          const handler = require("./v2").createSubmitCheckIn(admin);
          const receipt = await handler.run({auth: {uid: ctx.uid, token: {firebase: {sign_in_provider: "anonymous"}}},
            data: {eventId: ctx.eventId, sessionId: "", idempotencyKey: req.body.idempotencyKey,
              credential: {type: "location", position: req.body.position, registrationId: ctx.reg.id,
                fullName: ctx.reg.data().realName || ctx.reg.data().userName, ticketId: req.body.ticketId},
              answers: req.body.answers || [], observedAt: new Date().toISOString()}});
          return res.json(receipt);
        }
        return res.sendStatus(400);
      }
      if (req.method !== "GET") return res.sendStatus(405);
      const smart = await arrival.rollout(db, "smartArrival", ctx.eventId, ctx.uid) && core.arrivalPolicy(event.checkInPolicy).enabled;
      const passes = await arrival.rollout(db, "corePasses", ctx.eventId, ctx.uid);
      const questions = await db.collection("Events").doc(ctx.eventId).collection("EventQuestions").get();
      const answers = ctx.reg.data().answers || [];
      const required = require("./questions").requiredCheckInQuestions(questions.docs, answers);
      const eligibleTickets = await db.collection("Tickets").where("eventId", "==", ctx.eventId).where("customerUid", "==", ctx.uid).get();
      const ticketList = eligibleTickets.docs.filter((d) => core.validTicket(d.data(), event));
      const ticketChoice = ticketList.length > 1 ? `<label>Choose your ticket<select id="ticket"><option value="">Select a ticket</option>${ticketList.map((d) => `<option value="${escapeHtml(d.id)}">${escapeHtml(d.data().customerName || d.data().ticketCode || d.id)}</option>`).join("")}</select></label>` : "";
      const form = required.map((d) => `<label>${escapeHtml(d.title)}<input required name="answer" data-title="${escapeHtml(d.title)}" maxlength="400"></label>`).join("");
      return res.type("html").send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Your event pass | Attendus</title><link rel="stylesheet" href="/public-web/v1/public.css"></head><body><main class="page"><h1>${escapeHtml(event.title)}</h1><p>${escapeHtml(ctx.reg.data().realName || ctx.reg.data().userName)}</p>${ticketChoice}<form id="arrival">${smart ? `${form}<p>Allow a fresh location reading to find whether you are inside the venue. You will confirm before check-in is submitted. Location stops when you leave this page. You can also use the venue QR/code or ask staff.</p><button type="submit">Use my current location</button>` : ""}</form>${passes ? "<button id=\"wallet\" type=\"button\">Get my event pass</button>" : ""}<p id="status" role="status"></p><div id="wallet-links"></div><p><a href="/manage">Back to registration</a></p></main><script nonce="${nonce}">
const csrf=${JSON.stringify(ctx.session.csrfToken)};
const acquireLocation=${acquireGuestLocation.toString()};
const status=document.getElementById('status');
async function send(body){const selection=document.getElementById('ticket');if(selection&&!selection.value)throw Error('Select your individual ticket first.');body.ticketId=selection?.value;const response=await fetch('/manage/attendance',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...body,csrf})});const data=await response.json();if(!response.ok)throw Error(data.message||'Please try again.');return data;}
document.getElementById('wallet')?.addEventListener('click',async(event)=>{event.target.disabled=true;status.textContent='Preparing your pass…';try{const pass=await send({action:'wallet'});const links=document.getElementById('wallet-links');links.replaceChildren();if(pass.qrImage){const qr=document.createElement('img');qr.src=pass.qrImage;qr.alt='Your signed event admission pass';links.append(qr);}for(const [field,label] of [['appleWalletUrl','Add to Apple Wallet'],['googleWalletUrl','Add to Google Wallet']]){if(pass[field]){const a=document.createElement('a');a.href=pass[field];a.textContent=label;a.className='secondary-button';links.append(a);}}status.textContent=pass.passLockRequired?'This event requires device authentication to display its pass. Open your pass in the Attendus app, use the venue QR/code, or ask staff.':pass.qrImage?'Your event pass is ready. Show it to staff.':'Your pass could not be displayed. Retry, use the venue QR/code, or ask staff.';}catch(error){status.textContent=error.message;}finally{event.target.disabled=false;}});
document.getElementById('arrival').addEventListener('submit',async(event)=>{event.preventDefault();const button=event.target.querySelector('button');if(!button)return;button.disabled=true;status.textContent='Checking your location…';try{const position=await acquireLocation();if(!window.confirm('Confirm that you are at this venue and want to check in now.')){status.textContent='Check-in cancelled. You can retry when ready.';button.disabled=false;return;}if(document.hidden||Date.now()-position.timestamp>30000)throw Error('Your location reading expired. Please retry.');const answers=Array.from(event.target.querySelectorAll('input')).map(input=>input.dataset.title+'--ans--'+input.value.trim());await send({action:'arrival',idempotencyKey:crypto.randomUUID(),position:{latitude:position.coords.latitude,longitude:position.coords.longitude,accuracy:position.coords.accuracy,sampledAt:new Date(position.timestamp).toISOString()},answers});status.textContent='You are checked in. Enjoy your event!';}catch(error){status.textContent=error.message+' You can also use the venue code or ask staff.';button.disabled=false;}});
</script></body></html>`);
    } catch (error) {
      const code = error.code === "unauthenticated" ? 401 : error.code === "permission-denied" ? 403 : 400;
      if (req.method === "POST") return res.status(code).json({message: error.code ? error.message : "Attendance is temporarily unavailable."});
      return res.status(code).type("html").send(`<p>${escapeHtml(error.code ? error.message : "Attendance is temporarily unavailable.")}</p><a href="/manage">Back to registration</a>`);
    }
  });
}

module.exports = {guestContext, acquireGuestLocation, guestPassResponse, createGuestAttendanceWeb};
