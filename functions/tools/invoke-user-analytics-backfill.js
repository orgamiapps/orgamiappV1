"use strict";

const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const ALLOWED_PROJECTS = new Set(["attendus-staging", "orgami-66nxok"]);

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

async function jsonResponse(response, label) {
  const body = await response.json();
  if (!response.ok || body.error) {
    throw new Error(`${label} failed (${response.status}): ${JSON.stringify(body.error || body)}`);
  }
  return body;
}

async function main() {
  const projectId = argument("--project");
  const apiKey = argument("--api-key");
  const reason = argument("--reason");
  const requestedActorUid = argument("--actor-uid");
  const serviceAccountId = argument("--service-account");
  const apply = process.argv.includes("--apply");

  if (!apply || !ALLOWED_PROJECTS.has(projectId) || !apiKey ||
      !reason || reason.trim().length < 10 || reason.length > 500) {
    throw new Error(
        "Usage: node tools/invoke-user-analytics-backfill.js " +
        "--project <allowed-project> --api-key <web-api-key> " +
        "--reason <10-500 chars> --service-account <email> " +
        "[--actor-uid <uid>] --apply",
    );
  }
  if (!serviceAccountId ||
      !serviceAccountId.endsWith(`@${projectId}.iam.gserviceaccount.com`)) {
    throw new Error("A service account belonging to the selected project is required.");
  }

  initializeApp({projectId, serviceAccountId});
  const db = getFirestore();
  const roles = await db.collection("admin_roles")
      .where("active", "==", true).get();
  const eligible = roles.docs.filter((doc) => {
    const values = doc.get("roles") || [];
    return values.includes("super_admin") || values.includes("analyst");
  });
  const candidates = requestedActorUid ?
    eligible.filter((doc) => doc.id === requestedActorUid) : eligible;
  if (candidates.length !== 1) {
    throw new Error(
        `Expected exactly one eligible administrator; found ${candidates.length}. ` +
        "Pass --actor-uid when more than one is active.",
    );
  }

  const actorUid = candidates[0].id;
  await getAuth().getUser(actorUid);
  const customToken = await getAuth().createCustomToken(actorUid, {admin: true});
  const signInResponse = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({token: customToken, returnSecureToken: true}),
      },
  );
  const signIn = await jsonResponse(signInResponse, "Firebase token exchange");

  const callableResponse = await fetch(
      `https://us-central1-${projectId}.cloudfunctions.net/backfillUserAnalyticsV2`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${signIn.idToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          data: {confirmed: true, reason: reason.trim()},
        }),
      },
  );
  const callable = await jsonResponse(callableResponse, "Analytics backfill");
  console.log(JSON.stringify({
    projectId,
    actorUid,
    result: callable.result,
  }));
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
