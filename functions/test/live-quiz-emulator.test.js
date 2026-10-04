"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");
assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^(127\.0\.0\.1|localhost):\d+$/);
assert.equal(process.env.GCLOUD_PROJECT || "demo-attendus-admin", "demo-attendus-admin");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const admin = require("../firebase-admin-compat");
const {createQuizHandlers} = require("../quiz/service");
const {cleanupQuizAccountData} = require("../quiz/account-deletion");
const db = admin.firestore();
const fixtures = [];
const request = (uid, data, anonymous = false) => ({auth: {uid, token: {firebase: {sign_in_provider: anonymous ? "anonymous" : "password"}}}, data});
const question = {type: "multipleChoice", question: "Fixture question", options: ["Right", "Wrong"], correctOptionIndex: 0, timeLimit: 20, points: 100};

async function fixture(settings = {}, event = {}) {
  const suffix = randomUUID();
  const owner = `quiz-owner-${suffix}`;
  const player = `quiz-player-${suffix}`;
  const eventId = `quiz-event-${suffix}`;
  await db.collection("Events").doc(eventId).set({customerUid: owner, private: false, status: "active", ...event});
  let time = 100000;
  const handlers = createQuizHandlers(db, {now: () => time});
  const created = await handlers.mutation(request(owner, {action: "create", eventId, requestId: randomUUID(), payload: {title: "Quiz emulator fixture", autoAdvance: false, ...settings}}));
  const quizId = created.quizId;
  const read = (action, uid = owner, fields = {}) => handlers.read(request(uid, {action, quizId, ...fields})).then((value) => value.data);
  const act = async (action, uid = owner, payload = {}, fields = {}) => {
    const current = await db.collection("LiveQuizzes").doc(quizId).get();
    return handlers.mutation(request(uid, {action, quizId, payload, requestId: randomUUID(), expectedRevision: current.get("revision"), ...fields}));
  };
  const added = await act("addQuestion", owner, question);
  const value = {owner, player, eventId, quizId, questionId: added.questionId, handlers, read, act, tick: (delta) => { time += delta; }};
  fixtures.push(value);
  return value;
}

test.after(async () => {
  for (const f of fixtures) {
    for (const collection of ["QuizParticipants", "QuizResponses", "LiveQuizQuestionLookup"]) {
      const rows = await db.collection(collection).where("quizId", "==", f.quizId).get();
      for (const row of rows.docs) await row.ref.delete();
    }
    await db.recursiveDelete(db.collection("LiveQuizSecrets").doc(f.quizId));
    await db.collection("LiveQuizzes").doc(f.quizId).delete();
    await db.recursiveDelete(db.collection("Events").doc(f.eventId));
    await db.collection("account_deletion_jobs").doc(f.player).delete();
  }
  await db.terminate();
});

test("real transactions reserve one participant and one score across concurrent retries", async () => {
  const f = await fixture({maxParticipants: 1});
  const join = {action: "join", quizId: f.quizId, payload: {displayName: "Player"}};
  const joins = await Promise.all(Array.from({length: 5}, () => f.handlers.mutation(request(f.player, join))));
  assert.equal(new Set(joins.map((value) => value.participantId)).size, 1);
  await assert.rejects(f.act("join", `${f.player}-other`, {}), {code: "resource-exhausted"});
  await f.act("start"); f.tick(6000);
  const answer = {action: "submitAnswer", quizId: f.quizId, questionId: f.questionId, participantId: joins[0].participantId,
    payload: {answer: 0, session: 1, pointsEarned: 99999, timeToAnswer: 0}};
  const answers = await Promise.all(Array.from({length: 5}, () => f.handlers.mutation(request(f.player, answer))));
  assert.equal(answers[0].response.gradingPending, true);
  assert.equal(answers.every((value) => value.response.id === answers[0].response.id), true);
  const stored = await db.collection("QuizParticipants").doc(joins[0].participantId).get();
  assert.equal(stored.get("currentScore"), 130); assert.equal(stored.get("questionsAnswered"), 1);
  assert.equal((await f.read("participants", f.player))[0].currentScore, 0);
  await assert.rejects(f.handlers.mutation(request(f.player, {...answer, payload: {answer: 1, session: 1}})), {code: "already-exists"});
  f.tick(14000);
  assert.equal((await f.read("participantResponse", f.player, {questionId: f.questionId})).totalPoints, 130);
  assert.equal((await f.read("stats")).totalResponses, 1);
});

test("event membership, revocation, anonymous policy and cross-user answers are enforced", async () => {
  const f = await fixture({allowAnonymous: false}, {private: true});
  await assert.rejects(f.read("quiz", f.player), {code: "permission-denied"});
  await db.collection("Events").doc(f.eventId).collection("Attendees").doc(f.player).set({registered: true});
  await assert.rejects(f.handlers.mutation(request(f.player, {action: "join", quizId: f.quizId, payload: {}}, true)), {code: "permission-denied"});
  const joined = await f.act("join", f.player, {displayName: "Player"});
  await assert.rejects(f.act("start", f.player), {code: "permission-denied"});
  await f.act("start");
  await assert.rejects(f.act("submitAnswer", f.player, {answer: 0, session: 1}, {participantId: "someone-else", questionId: f.questionId}), {code: "permission-denied"});
  await assert.rejects(f.read("participantResponse", f.player, {questionId: f.questionId, participantId: "someone-else"}), {code: "permission-denied"});
  assert.equal((await f.handlers.read(request(f.player, {action: "participant", participantId: joined.participantId}))).data.id, joined.participantId);
  await db.collection("Events").doc(f.eventId).update({customerUid: `${f.owner}-replacement`});
  await assert.rejects(f.act("end"), {code: "permission-denied"});
  await db.collection("account_deletion_jobs").doc(f.player).set({status: "running"});
  await assert.rejects(f.read("quiz", f.player), {code: "failed-precondition"});
});

test("server question deadlines, redaction, restarts and stale lifecycle requests stay fenced", async () => {
  const f = await fixture({autoAdvance: true});
  const second = await f.act("addQuestion", f.owner, {...question, timeLimit: 10});
  await f.act("join", f.player); await f.act("start");
  const first = await f.read("currentQuestion", f.player);
  assert.equal(first.session, 1); assert.equal(first.quizId, f.quizId);
  assert.equal(Object.hasOwn(first, "correctOptionIndex"), false);
  const revision = (await f.read("quiz")).revision;
  f.tick(20000);
  await assert.rejects(f.act("submitAnswer", f.player, {answer: 0, session: 1}, {questionId: f.questionId}), {code: "failed-precondition"});
  assert.equal((await f.read("currentQuestion", f.player)).id, second.questionId);
  await assert.rejects(f.act("next", f.owner, {}, {expectedRevision: revision}), {code: "aborted"});
  f.tick(10000); assert.equal((await f.read("quiz")).status, "ended");
  await f.act("restart", f.owner, {keepParticipants: true}); await f.act("start");
  await assert.rejects(f.act("submitAnswer", f.player, {answer: 0, session: 1}, {questionId: f.questionId}), {code: "failed-precondition"});
  assert.equal((await f.read("currentQuestion", f.player)).session, 2);
});

test("participant cleanup retains other participants and host data, including legacy answer cleanup", async () => {
  const f = await fixture();
  const joined = await f.act("join", f.player);
  const other = await f.act("join", `${f.player}-other`);
  await f.act("start");
  await f.act("submitAnswer", f.player, {answer: 0, session: 1}, {questionId: f.questionId});
  await db.collection("QuizResponses").doc(`legacy-${f.player}`).set({quizId: f.quizId, participantId: joined.participantId, answer: "old"});
  const job = db.collection("account_deletion_jobs").doc(f.player);
  await job.set({status: "running"});
  const counts = {};
  Object.defineProperties(counts, {job: {value: job}, lease: {value: {transaction: (fn) => db.runTransaction(fn)}}});
  await cleanupQuizAccountData(db, f.player, counts);
  await cleanupQuizAccountData(db, f.player, counts);
  assert.equal(counts.quizResponsesDeleted, 2); assert.equal(counts.quizParticipantsDeleted, 1);
  assert.equal((await db.collection("QuizParticipants").doc(other.participantId).get()).exists, true);
  assert.equal((await db.collection("QuizParticipants").doc(joined.participantId).get()).exists, false);
  assert.equal((await db.collection("QuizResponses").where("quizId", "==", f.quizId).get()).empty, true);
  assert.equal((await f.read("quiz")).participantCount, 1);
  assert.equal((await db.collection("LiveQuizSecrets").doc(f.quizId).get()).exists, true);
});

test("direct Firestore access cannot read answer secrets or forge quiz state and scores", async () => {
  const f = await fixture();
  const env = await initializeTestEnvironment({projectId: "demo-attendus-admin",
    firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  try {
    for (const uid of [f.owner, f.player]) {
      const client = env.authenticatedContext(uid).firestore();
      for (const collection of ["LiveQuizzes", "LiveQuizSecrets", "LiveQuizQuestionLookup", "QuizQuestions", "QuizParticipants", "QuizResponses"]) {
        await assertFails(getDoc(doc(client, collection, f.quizId)));
        await assertFails(setDoc(doc(client, collection, f.quizId), {currentScore: 999999, correctOptionIndex: 0}));
      }
      await assertFails(getDoc(doc(client, "LiveQuizSecrets", f.quizId, "operations", "private-marker")));
    }
  } finally { await env.cleanup(); }
});
