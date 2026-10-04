"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createQuizHandlers, question, grade, advance} = require("../quiz/service");
const {cleanupQuizAccountData} = require("../quiz/account-deletion");
const clone = (value) => value === undefined ? undefined : structuredClone(value);

// Transactions are isolated and buffered, and forbid reads after any write just
// like Firestore. Tests exercise handlers rather than mock their authorization.
function memoryDatabase() {
  let documents = new Map();
  let queue = Promise.resolve();
  const snapshot = (reference, data) => ({ref: reference, id: reference.id,
    exists: data !== undefined, data: () => clone(data), get: (key) => clone(data?.[key])});
  const document = (path) => ({path, id: path.split("/").at(-1), collection: (key) => collection(`${path}/${key}`)});
  const collection = (path, filters = [], maximum = Infinity) => ({path, filters, maximum,
    doc: (key) => document(`${path}/${key}`),
    where: (field, operator, value) => { assert.equal(operator, "=="); return collection(path, [...filters, [field, value]], maximum); },
    limit: (limit) => collection(path, filters, limit),
    get: async () => {
      const docs = [...documents].filter(([key, value]) => key.startsWith(`${path}/`) && key.split("/").length === path.split("/").length + 1 && filters.every(([field, expected]) => value[field] === expected))
          .slice(0, maximum).map(([key, value]) => snapshot(document(key), value));
      return {docs, size: docs.length, empty: !docs.length};
    }});
  return {collection,
    put: (path, data) => documents.set(path, clone(data)),
    peek: (path) => clone(documents.get(path)),
    all: (path) => [...documents].filter(([key]) => key.startsWith(`${path}/`) && key.split("/").length === path.split("/").length + 1).map(([, data]) => clone(data)),
    runTransaction: (callback) => {
      const run = queue.then(async () => {
        const draft = new Map([...documents].map(([key, value]) => [key, clone(value)]));
        let writing = false;
        const tx = {
          get: async (reference) => {
            assert.equal(writing, false, "Firestore reads must precede writes");
            if (reference.id) return snapshot(reference, draft.get(reference.path));
            const docs = [...draft].filter(([key, value]) => key.startsWith(`${reference.path}/`) &&
              key.split("/").length === reference.path.split("/").length + 1 && reference.filters.every(([field, expected]) => value[field] === expected))
                .slice(0, reference.maximum).map(([key, value]) => snapshot(document(key), value));
            return {docs, size: docs.length, empty: !docs.length};
          },
          set: (reference, data) => { writing = true; draft.set(reference.path, clone(data)); },
          create: (reference, data) => { assert.equal(draft.has(reference.path), false); tx.set(reference, data); },
          update: (reference, data) => { assert.equal(draft.has(reference.path), true); tx.set(reference, {...draft.get(reference.path), ...data}); },
          delete: (reference) => { writing = true; draft.delete(reference.path); },
        };
        const result = await callback(tx);
        documents = draft;
        return result;
      });
      queue = run.catch(() => {});
      return run;
    },
  };
}

const request = (uid, data, anonymous = false) => ({auth: uid ? {uid, token: {firebase: {sign_in_provider: anonymous ? "anonymous" : "password"}}} : null, data});
const sample = (extra = {}) => ({type: "multipleChoice", question: "Choose the correct option", options: ["Correct", "Incorrect"], correctOptionIndex: 0, timeLimit: 20, points: 100, explanation: "Private explanation", ...extra});

async function fixture(extra = {}) {
  const db = memoryDatabase();
  db.put("Events/event", {customerUid: "host", private: false, status: "active", ...extra.event});
  let time = 100000;
  let sequence = 0;
  const handlers = createQuizHandlers(db, {now: () => time});
  const create = await handlers.mutation(request("host", {action: "create", eventId: "event", requestId: "create-unique-request", payload: {title: "Quiz", autoAdvance: false, ...extra.settings}}));
  const quizId = create.quizId;
  const act = (action, payload = {}, data = {}, uid = "host", anonymous = false) => handlers.mutation(request(uid, {quizId, action, payload,
    requestId: `unique-request-${++sequence}`, expectedRevision: db.peek(`LiveQuizzes/${quizId}`).revision, ...data}, anonymous));
  const read = (action, data = {}, uid = "host", anonymous = false) => handlers.read(request(uid, {quizId, action, ...data}, anonymous)).then((value) => value.data);
  const add = await act("addQuestion", sample());
  const join = (uid = "player", anonymous = false) => act("join", {displayName: uid}, {}, uid, anonymous);
  const submit = (answer = 0, data = {}, uid = "player") => act("submitAnswer", {answer, session: db.peek(`LiveQuizzes/${quizId}`).session}, {questionId: add.questionId, ...data}, uid);
  return {db, handlers, quizId, questionId: add.questionId, act, read, join, submit, tick: (delta) => { time += delta; }};
}

test("quiz validates bounded settings, questions and server scoring", () => {
  const value = question(sample(), "quiz", "question", 0);
  assert.equal(grade(value, 0, 1000).totalPoints, 150);
  assert.equal(grade(value, 0, 6000).totalPoints, 130);
  assert.equal(grade(value, 1, 1000).totalPoints, 0);
  assert.throws(() => question(sample({correctOptionIndex: 20}), "quiz", "question", 0), {code: "invalid-argument"});
  assert.throws(() => question(sample({timeLimit: 0}), "quiz", "question", 0), {code: "invalid-argument"});
  const short = question(sample({type: "shortAnswer", acceptableAnswers: ["Alpha"]}), "quiz", "question", 0);
  assert.equal(grade(short, "  ALPHA ", 1000).isCorrect, true);
  assert.equal(grade(short, "Alp", 1000).isCorrect, false);
  assert.throws(() => advance({status: "live", autoAdvance: true}, [], 100), {code: "failed-precondition"});
});

test("host operations are idempotent, fingerprint-bound and role checked on retry", async () => {
  const f = await fixture();
  const data = {action: "addQuestion", quizId: f.quizId, requestId: "same-host-request", payload: sample()};
  const [a, b] = await Promise.all([f.handlers.mutation(request("host", data)), f.handlers.mutation(request("host", data))]);
  assert.deepEqual(a, b);
  assert.equal(f.db.peek(`LiveQuizzes/${f.quizId}`).totalQuestions, 2);
  await assert.rejects(f.handlers.mutation(request("host", {...data, payload: sample({question: "Different"})})), {code: "already-exists"});
  f.db.put("Events/event", {customerUid: "new-host"});
  await assert.rejects(f.handlers.mutation(request("host", data)), {code: "permission-denied"});
});

test("anonymous, non-host, private-event and account-deletion boundaries fail closed", async () => {
  const f = await fixture({event: {private: true}});
  await assert.rejects(f.join(), {code: "permission-denied"});
  await assert.rejects(f.read("quiz", {}, null), {code: "unauthenticated"});
  f.db.put("Events/event/Attendees/player", {registered: true});
  await f.join();
  await assert.rejects(f.act("start", {}, {}, "player"), {code: "permission-denied"});
  await assert.rejects(f.act("start", {}, {}, "host", true), {code: "permission-denied"});
  f.db.put("account_deletion_jobs/player", {status: "running"});
  await assert.rejects(f.read("quiz", {}, "player"), {code: "failed-precondition"});
});

test("anonymous join obeys quiz policy and never gains host authority", async () => {
  const f = await fixture({settings: {allowAnonymous: false}});
  await assert.rejects(f.join("guest", true), {code: "permission-denied"});
  await f.join();
  await assert.rejects(f.act("join", {isAnonymous: true}, {}, "other"), {code: "permission-denied"});
});

test("question reads redact private answers and bind the same quiz session", async () => {
  const f = await fixture();
  assert.deepEqual(await f.read("questions", {}, "player"), []);
  await f.act("start");
  const visible = await f.read("currentQuestion", {}, "player");
  assert.equal(visible.quizId, f.quizId);
  assert.equal(visible.session, 1);
  for (const field of ["correctOptionIndex", "acceptableAnswers", "explanation"]) assert.equal(Object.hasOwn(visible, field), false);
  assert.equal((await f.read("currentQuestion")).correctOptionIndex, 0);
  const lookup = await f.handlers.read(request("host", {action: "questionResponses", questionId: f.questionId}));
  assert.deepEqual(lookup.data, []);
  await assert.rejects(f.handlers.read(request("player", {action: "questionResponses", questionId: f.questionId})), {code: "permission-denied"});
});

test("concurrent answer retries score exactly once and ignore client timing/score", async () => {
  const f = await fixture();
  const {participantId} = await f.join();
  await f.act("start"); f.tick(6000);
  const payload = {answer: 0, session: 1, pointsEarned: 90000, isCorrect: false, timeToAnswer: 0, questionIndex: 99};
  const [a, b] = await Promise.all([f.act("submitAnswer", payload, {questionId: f.questionId}, "player"), f.act("submitAnswer", payload, {questionId: f.questionId}, "player")]);
  assert.deepEqual(a.response, b.response);
  assert.equal(a.response.gradingPending, true);
  assert.equal(Object.hasOwn(a.response, "isCorrect"), false);
  assert.equal(f.db.all("QuizResponses").length, 1);
  assert.equal(f.db.peek(`QuizParticipants/${participantId}`).currentScore, 130);
  assert.equal((await f.read("participant", {}, "player")).currentScore, 0);
  assert.equal((await f.read("participants", {}, "player"))[0].currentScore, 0);
  await assert.rejects(f.submit(1), {code: "already-exists"});
  f.tick(15000);
  const scored = await f.read("participantResponse", {questionId: f.questionId}, "player");
  assert.equal(scored.gradingPending, false); assert.equal(scored.totalPoints, 130); assert.equal(scored.timeToAnswer, 6000);
  assert.equal((await f.read("participant", {}, "player")).currentScore, 130);
  assert.equal((await f.submit()).response.totalPoints, 130);
});

test("participant IDs cannot impersonate another caller or expose private responses", async () => {
  const f = await fixture();
  const player = await f.join();
  const other = await f.join("other");
  await f.act("start");
  await assert.rejects(f.submit(0, {participantId: other.participantId}), {code: "permission-denied"});
  await assert.rejects(f.read("participant", {participantId: other.participantId}, "player"), {code: "permission-denied"});
  await assert.rejects(f.read("participantResponse", {questionId: f.questionId, participantId: other.participantId}, "player"), {code: "permission-denied"});
  const result = await f.handlers.read(request("player", {action: "participant", participantId: player.participantId}));
  assert.equal(result.data.id, player.participantId); assert.equal(Object.hasOwn(result.data, "userId"), false);
});

test("pause freezes time and rejects answers; resume preserves elapsed scoring time", async () => {
  const f = await fixture();
  const {participantId} = await f.join(); await f.act("start"); f.tick(6000); await f.act("pause");
  f.tick(100000);
  await assert.rejects(f.submit(), {code: "failed-precondition"});
  await f.act("resume"); f.tick(1000);
  await f.submit();
  const response = await f.read("participantResponse", {questionId: f.questionId, participantId});
  assert.equal(response.timeToAnswer, 7000); assert.equal(response.totalPoints, 130);
  await assert.rejects(f.act("addQuestion", sample()), {code: "failed-precondition"});
});

test("server deadline closes late answers; reads deterministically advance timed questions", async () => {
  const f = await fixture({settings: {autoAdvance: true}});
  const second = await f.act("addQuestion", sample({timeLimit: 10}));
  await f.join(); await f.act("start"); f.tick(20000);
  await assert.rejects(f.submit(), {code: "failed-precondition"});
  const current = await f.read("currentQuestion", {}, "player");
  assert.equal(current.id, second.questionId);
  assert.equal((await f.read("quiz")).currentQuestionStartedAt, 120000);
  f.tick(10000);
  assert.equal((await f.read("quiz")).status, "ended");
});

test("host lifecycle rejects stale revisions and safe repeat does not skip a question", async () => {
  const f = await fixture();
  await f.act("addQuestion", sample()); await f.act("start");
  const revision = f.db.peek(`LiveQuizzes/${f.quizId}`).revision;
  await assert.rejects(f.act("next", {}, {expectedRevision: revision - 1}), {code: "aborted"});
  const data = {action: "next", quizId: f.quizId, expectedRevision: revision, requestId: "next-repeat-request", payload: {}};
  assert.deepEqual(await f.handlers.mutation(request("host", data)), await f.handlers.mutation(request("host", data)));
  assert.equal((await f.read("quiz")).currentQuestionIndex, 1);
});

test("restart fences old answers and lazily resets retained participant scores", async () => {
  const f = await fixture(); await f.join(); await f.act("start"); await f.submit(); await f.act("end");
  await f.act("restart", {keepParticipants: true}); await f.act("start");
  assert.equal((await f.read("participant", {}, "player")).currentScore, 0);
  await assert.rejects(f.act("submitAnswer", {answer: 0, session: 1}, {questionId: f.questionId}, "player"), {code: "failed-precondition"});
  await f.submit(); await f.act("end");
  assert.equal((await f.read("participant", {}, "player")).currentScore, 150);
  assert.equal(f.db.all("QuizResponses").length, 2);
  await f.act("restart", {keepParticipants: false});
  assert.equal(await f.read("participant", {}, "player"), null);
  await assert.rejects(f.submit(), {code: "permission-denied"});
});

test("join/leave counts are idempotent and run enrollment prevents capacity cycling", async () => {
  const f = await fixture({settings: {maxParticipants: 1}});
  const [a, b] = await Promise.all([f.join(), f.join()]); assert.equal(a.participantId, b.participantId);
  await assert.rejects(f.join("other"), {code: "resource-exhausted"});
  await f.act("leave", {}, {}, "player"); await f.act("leave", {}, {}, "player");
  assert.equal((await f.read("quiz")).participantCount, 0);
  await assert.rejects(f.join("other"), {code: "resource-exhausted"});
  await f.join(); assert.equal((await f.read("quiz")).participantCount, 1);
});

test("inactive prior-run leave cannot create a free enrollment in a restarted run", async () => {
  const f = await fixture({settings: {maxParticipants: 1}});
  await f.join(); await f.act("leave", {}, {}, "player"); await f.act("start"); await f.act("end");
  await f.act("restart", {keepParticipants: true}); await f.act("leave", {}, {}, "player");
  await f.join(); await f.act("leave", {}, {}, "player");
  await assert.rejects(f.join("other"), {code: "resource-exhausted"});
});

test("hidden leaderboard returns only self and deletes hide event/quiz with repeat safety", async () => {
  const f = await fixture({settings: {showLeaderboard: false}});
  const player = await f.join(); await f.join("other");
  assert.deepEqual((await f.read("participants", {}, "player")).map((item) => item.id), [player.participantId]);
  const data = {action: "delete", quizId: f.quizId, requestId: "delete-repeat-request", payload: {}};
  assert.deepEqual(await f.handlers.mutation(request("host", data)), await f.handlers.mutation(request("host", data)));
  assert.equal(f.db.peek("Events/event").liveQuizId, null);
  await assert.rejects(f.read("quiz", {}, "player"), {code: "not-found"});
  assert.equal((await f.handlers.read(request("player", {action: "getByEvent", eventId: "event"}))).data, null);
});

test("account cleanup removes only the subject, reconciles counters, and is idempotent", async () => {
  const f = await fixture();
  const player = await f.join(); const other = await f.join("other");
  await f.act("start"); await f.submit(); await f.submit(1, {}, "other");
  f.db.put("QuizResponses/legacy-answer", {quizId: f.quizId, participantId: player.participantId, answer: "legacy"});
  const counts = {};
  Object.defineProperties(counts, {
    lease: {value: {transaction: f.db.runTransaction}}, job: {value: f.db.collection("account_deletion_jobs").doc("player")},
  });
  f.db.put("account_deletion_jobs/player", {status: "running"});
  await cleanupQuizAccountData(f.db, "player", counts);
  assert.equal(counts.quizResponsesDeleted, 2); assert.equal(counts.quizParticipantsDeleted, 1);
  assert.equal(f.db.peek(`QuizParticipants/${player.participantId}`), undefined);
  assert.equal(f.db.peek(`QuizParticipants/${other.participantId}`).isActive, true);
  assert.equal(f.db.all("QuizResponses").length, 1);
  const quiz = f.db.peek(`LiveQuizzes/${f.quizId}`);
  assert.equal(quiz.participantCount, 1); assert.equal(quiz.enrolledCount, 1);
  assert.equal(quiz.totalResponses, 1); assert.equal(quiz.correctResponses, 0);
  await cleanupQuizAccountData(f.db, "player", counts);
  assert.equal(counts.quizResponsesDeleted, 2); assert.equal(counts.quizParticipantsDeleted, 1);
});

test("lost deletion lease does not delete participant provenance or answers", async () => {
  const f = await fixture(); const player = await f.join(); await f.act("start"); await f.submit();
  const counts = {};
  Object.defineProperties(counts, {lease: {value: {transaction: async () => { throw Error("lease lost"); }}},
    job: {value: f.db.collection("account_deletion_jobs").doc("player")}});
  await assert.rejects(cleanupQuizAccountData(f.db, "player", counts), /lease lost/);
  assert.equal(f.db.peek(`QuizParticipants/${player.participantId}`).isActive, true);
  assert.equal(f.db.all("QuizResponses").length, 1);
});

test("legacy response ownership conflicts require review before deleting the owner link", async () => {
  const f = await fixture(); const player = await f.join();
  f.db.put("QuizResponses/conflicting-answer", {quizId: f.quizId, participantId: player.participantId, userId: "other", answer: "conflict"});
  const counts = {};
  Object.defineProperties(counts, {lease: {value: {transaction: f.db.runTransaction}},
    job: {value: f.db.collection("account_deletion_jobs").doc("player")}});
  await assert.rejects(cleanupQuizAccountData(f.db, "player", counts), {code: "deletion/review-required"});
  assert.equal(f.db.peek(`QuizParticipants/${player.participantId}`).isActive, true);
  assert.equal(f.db.all("QuizResponses").length, 1);
});

module.exports = {memoryDatabase, request, sample};
