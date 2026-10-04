"use strict";

const crypto = require("node:crypto");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {capabilities} = require("../events/access");
const fail = (code, message) => { throw new HttpsError(code, message); };
const hash = (...parts) => crypto.createHash("sha256").update(JSON.stringify(parts)).digest("hex");
const id = (value) => typeof value === "string" && /^[A-Za-z0-9._:-]{1,160}$/.test(value) ? value : fail("invalid-argument", "A valid identifier is required.");
const integer = (value, min, max) => Number.isInteger(value) && value >= min && value <= max ? value : fail("invalid-argument", "A setting is outside its supported range.");
const text = (value, maximum, optional = false) => {
  if (optional && (value === null || value === undefined || value === "")) return null;
  if (typeof value !== "string" || !value.trim() || value.length > maximum) fail("invalid-argument", "Quiz text is missing or too long.");
  return value.trim();
};
const canonical = (value) => Array.isArray(value) ? value.map(canonical) : value && typeof value === "object" ?
  Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])])) : value;
const SETTINGS = ["title", "description", "timePerQuestion", "autoAdvance", "showLeaderboard", "allowAnonymous", "maxParticipants"];

function settings(payload, previous = {}) {
  if (Object.keys(payload).some((key) => !SETTINGS.includes(key))) fail("invalid-argument", "Unsupported quiz setting.");
  const value = {timePerQuestion: 30, autoAdvance: true, showLeaderboard: true, allowAnonymous: true, maxParticipants: 1000, ...previous, ...payload};
  const output = {title: text(value.title, 160), description: text(value.description, 2000, true),
    timePerQuestion: integer(value.timePerQuestion, 5, 300), maxParticipants: integer(value.maxParticipants, 1, 1000)};
  for (const key of ["autoAdvance", "showLeaderboard", "allowAnonymous"]) {
    if (typeof value[key] !== "boolean") fail("invalid-argument", "Quiz switches must be boolean.");
    output[key] = value[key];
  }
  return output;
}

function question(payload, quizId, questionId, orderIndex) {
  const type = payload.type;
  if (!["multipleChoice", "trueFalse", "shortAnswer"].includes(type)) fail("invalid-argument", "Unsupported question type.");
  if (payload.quizId && payload.quizId !== quizId) fail("invalid-argument", "Question belongs to a different quiz.");
  const options = type === "trueFalse" ? ["True", "False"] : type === "shortAnswer" ? [] : payload.options;
  if (!Array.isArray(options) || (type === "multipleChoice" && (options.length < 2 || options.length > 8))) fail("invalid-argument", "Choose between two and eight options.");
  const answers = type === "shortAnswer" ? payload.acceptableAnswers : [];
  if (!Array.isArray(answers) || (type === "shortAnswer" && (!answers.length || answers.length > 20))) fail("invalid-argument", "Provide one to twenty acceptable answers.");
  if (payload.caseSensitive !== undefined && typeof payload.caseSensitive !== "boolean") fail("invalid-argument", "Invalid answer matching setting.");
  const imageUrl = text(payload.imageUrl, 2000, true);
  if (imageUrl && !/^https:\/\//.test(imageUrl)) fail("invalid-argument", "Question images require HTTPS.");
  const result = {id: questionId, quizId, orderIndex, type, question: text(payload.question, 2000), imageUrl,
    options: options.map((option) => text(option, 500)), acceptableAnswers: answers.map((answer) => text(answer, 200)),
    correctOptionIndex: type === "shortAnswer" ? null : integer(payload.correctOptionIndex, 0, options.length - 1),
    caseSensitive: payload.caseSensitive === true, timeLimit: integer(payload.timeLimit ?? 30, 5, 300),
    points: integer(payload.points ?? 100, 0, 1000), explanation: text(payload.explanation, 2000, true)};
  if (Buffer.byteLength(JSON.stringify(result)) > 8000) fail("invalid-argument", "Question is too large.");
  return result;
}

function openQuestion(quiz, questions, index, startedAt) {
  const current = questions[index];
  if (!current) return {...quiz, status: "ended", endedAt: startedAt, currentQuestionEndsAt: null};
  return {...quiz, status: "live", currentQuestionIndex: index, currentQuestionId: current.id,
    currentQuestionStartedAt: startedAt, currentQuestionTimeLimit: current.timeLimit,
    currentQuestionEndsAt: startedAt + current.timeLimit * 1000, elapsedBeforeMs: 0, questionRemainingMs: null};
}

function advance(quiz, questions, now) {
  let state = {...quiz};
  if (state.status === "live" && (!Number.isFinite(state.currentQuestionEndsAt) || !Number.isInteger(state.currentQuestionIndex) || !questions[state.currentQuestionIndex])) fail("failed-precondition", "Quiz timing requires organizer recovery.");
  while (state.status === "live" && state.autoAdvance && now >= state.currentQuestionEndsAt) {
    state = openQuestion(state, questions, state.currentQuestionIndex + 1, state.currentQuestionEndsAt);
    state.revision++;
  }
  return state;
}

function grade(current, answer, elapsed) {
  let correct;
  if (current.type === "shortAnswer") {
    const value = text(answer, 500);
    const normalize = (item) => current.caseSensitive ? item.trim() : item.trim().toLowerCase();
    correct = current.acceptableAnswers.some((item) => normalize(item) === normalize(value));
  } else {
    integer(answer, 0, current.options.length - 1);
    correct = answer === current.correctOptionIndex;
  }
  const ratio = elapsed / (current.timeLimit * 1000);
  const pointsEarned = correct ? current.points : 0;
  const speedBonusPoints = correct ? Math.round(pointsEarned * (ratio <= 0.25 ? 0.5 : ratio <= 0.5 ? 0.3 : ratio <= 0.75 ? 0.1 : 0)) : 0;
  return {isCorrect: correct, pointsEarned, speedBonusPoints, totalPoints: pointsEarned + speedBonusPoints,
    timeToAnswer: elapsed, questionTimeLimit: current.timeLimit, isLate: false, similarityScore: null};
}

function publicQuestion(value) {
  const visible = {...value};
  for (const key of ["correctOptionIndex", "acceptableAnswers", "explanation"]) delete visible[key];
  return visible;
}

function currentParticipant(participant, quiz) {
  if (!participant || participant.membershipEpoch !== quiz.membershipEpoch) return null;
  const current = participant.session === quiz.session ? participant : {...participant, session: quiz.session,
    currentScore: 0, questionsAnswered: 0, correctAnswers: 0, currentRank: null, bestRank: null};
  const visible = {...current};
  delete visible.userId;
  return visible;
}

function questionOpen(quiz, questionId, time) {
  return quiz.currentQuestionId === questionId && (quiz.status === "paused" ||
    (quiz.status === "live" && time < quiz.currentQuestionEndsAt));
}

function visibleResponse(response, quiz, time, host = false) {
  const visible = {...response, gradingPending: !host && questionOpen(quiz, response.questionId, time)};
  delete visible.userId;
  if (visible.gradingPending) for (const key of ["isCorrect", "pointsEarned", "speedBonusPoints", "totalPoints", "similarityScore"]) delete visible[key];
  return visible;
}

function visibleParticipant(participant, pending) {
  if (!participant || !pending) return participant;
  return {...participant, currentScore: participant.currentScore - pending.totalPoints,
    questionsAnswered: participant.questionsAnswered - 1, correctAnswers: participant.correctAnswers - (pending.isCorrect ? 1 : 0)};
}

function createQuizHandlers(db, {now = Date.now, eventCapabilities = capabilities} = {}) {
  const ref = (name, key) => db.collection(name).doc(key);
  function actor(request) {
    if (!request.auth?.uid) fail("unauthenticated", "Open a signed-in or guest session to join a quiz.");
    return id(request.auth.uid);
  }
  async function eventAccess(tx, request, eventId) {
    const uid = actor(request);
    const [document, deletion] = await Promise.all([tx.get(ref("Events", id(eventId))), tx.get(ref("account_deletion_jobs", uid))]);
    if (deletion.exists) fail("failed-precondition", "Account deletion is in progress.");
    if (!document.exists || ["deleted", "cancelled"].includes(document.get("status"))) fail("not-found", "This event is unavailable.");
    const event = document.data();
    const anonymous = request.auth.token?.firebase?.sign_in_provider === "anonymous";
    const permissions = await eventCapabilities(db, uid, event, tx);
    const host = !anonymous && permissions.manageEvent;
    if (!host && (event.private === true || ["draft", "unpublished", "suspended"].includes(event.status))) {
      const attendee = await tx.get(document.ref.collection("Attendees").doc(uid));
      if (!permissions.operateDoor && !(event.accessList || []).includes(uid) && !attendee.exists) fail("permission-denied", "Event access is required.");
    }
    return {uid, host, anonymous, event, document};
  }
  async function load(tx, request, time) {
    const data = request.data || {};
    let quizId = data.quizId;
    if (!quizId && data.participantId) {
      const participant = await tx.get(ref("QuizParticipants", id(data.participantId)));
      quizId = participant.get("quizId");
    }
    if (!quizId && data.questionId) {
      const lookup = await tx.get(ref("LiveQuizQuestionLookup", id(data.questionId)));
      quizId = lookup.get("quizId");
    }
    if (!quizId && data.eventId) {
      const access = await eventAccess(tx, request, data.eventId);
      quizId = access.event.liveQuizId;
      if (!quizId) return null;
    }
    if (!quizId) return null;
    const document = await tx.get(ref("LiveQuizzes", id(quizId)));
    if (!document.exists) fail("not-found", "Quiz not found.");
    const access = await eventAccess(tx, request, document.get("eventId"));
    if (data.eventId && data.eventId !== document.get("eventId")) fail("invalid-argument", "Quiz belongs to another event.");
    if (document.get("deletedAt") && !(access.host && data.action === "delete")) fail("not-found", "Quiz not found.");
    const secret = await tx.get(ref("LiveQuizSecrets", document.id));
    if (!secret.exists || document.get("schemaVersion") !== 1) fail("failed-precondition", "This legacy quiz requires organizer recovery.");
    const questions = secret.get("questions") || [];
    const original = {...document.data(), id: document.id};
    return {...access, document, secret, questions, original, quiz: advance(original, questions, time)};
  }
  const save = (tx, state) => {
    if (JSON.stringify(state.original) !== JSON.stringify(state.quiz)) tx.set(state.document.ref, state.quiz);
  };

  async function mutation(request) {
    const uid = actor(request);
    const data = request.data || {};
    const payload = data.payload || {};
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) fail("invalid-argument", "Invalid quiz payload.");
    const action = data.action;
    const hostAction = !["join", "leave", "submitAnswer"].includes(action);
    const requestId = hostAction ? id(data.requestId) : null;
    if (hostAction && requestId.length < 12) fail("invalid-argument", "A stable request identity is required.");
    return db.runTransaction(async (tx) => {
      const time = now();
      if (action === "create") {
        const access = await eventAccess(tx, request, data.eventId);
        if (!access.host) fail("permission-denied", "Only event managers can create a quiz.");
        const quizId = hash(data.eventId, uid, requestId);
        const document = await tx.get(ref("LiveQuizzes", quizId));
        const fingerprint = hash(canonical(payload));
        if (document.exists) {
          if (document.get("createFingerprint") !== fingerprint) fail("already-exists", "Request identity was used for different settings.");
          return {ok: true, quizId, revision: document.get("revision")};
        }
        if (access.event.liveQuizId) {
          const existing = await tx.get(ref("LiveQuizzes", access.event.liveQuizId));
          if (existing.exists && !existing.get("deletedAt")) fail("already-exists", "This event already has a quiz.");
        }
        const quiz = {id: quizId, eventId: data.eventId, creatorId: uid, ...settings(payload), schemaVersion: 1,
          createFingerprint: fingerprint, status: "draft", createdAt: time, startedAt: null, endedAt: null,
          currentQuestionIndex: null, currentQuestionId: null, currentQuestionStartedAt: null,
          totalQuestions: 0, participantCount: 0, enrolledCount: 0, totalResponses: 0, correctResponses: 0,
          revision: 1, session: 1, membershipEpoch: 1};
        tx.create(ref("LiveQuizzes", quizId), quiz);
        tx.create(ref("LiveQuizSecrets", quizId), {questions: []});
        tx.update(access.document.ref, {hasLiveQuiz: true, liveQuizId: quizId});
        return {ok: true, quizId, revision: 1};
      }
      const state = await load(tx, request, time);
      if (!state) fail("not-found", "Quiz not found.");
      let {quiz, questions} = state;
      if (hostAction) {
        if (!state.host) fail("permission-denied", "Only event managers can control a quiz.");
        const operationRef = state.secret.ref.collection("operations").doc(hash(uid, requestId));
        const previous = await tx.get(operationRef);
        const fingerprint = hash(action, data.questionId || null, canonical(payload));
        if (previous.exists) {
          if (previous.get("fingerprint") !== fingerprint) fail("already-exists", "Request identity was used for another action.");
          return previous.get("result");
        }
        if (quiz.deletedAt) fail("not-found", "Quiz not found.");
        if (["start", "pause", "resume", "next", "end", "restart"].includes(action) && data.expectedRevision !== quiz.revision) fail("aborted", "Quiz changed. Refresh its state before continuing.");
        let questionId = data.questionId;
        if (["update", "addQuestion", "updateQuestion", "deleteQuestion", "reorderQuestions"].includes(action) && quiz.status !== "draft") fail("failed-precondition", "Question settings are frozen during a quiz. Restart before editing.");
        if (action === "update") {
          const configured = settings(payload, quiz);
          if (configured.maxParticipants < quiz.enrolledCount) fail("failed-precondition", "Capacity cannot be lower than current membership.");
          quiz = {...quiz, ...configured};
        } else if (action === "addQuestion") {
          if (questions.length >= 100) fail("resource-exhausted", "A quiz supports up to 100 questions.");
          questionId = hash(quiz.id, requestId);
          questions = [...questions, question(payload, quiz.id, questionId, questions.length)];
        } else if (["updateQuestion", "deleteQuestion"].includes(action)) {
          const index = questions.findIndex((item) => item.id === id(questionId));
          if (index < 0) fail("not-found", "Question not found.");
          questions = action === "deleteQuestion" ? questions.filter((item) => item.id !== questionId) :
            questions.map((item, position) => position === index ? question({...item, ...payload}, quiz.id, item.id, position) : item);
          questions = questions.map((item, orderIndex) => ({...item, orderIndex}));
        } else if (action === "reorderQuestions") {
          const ids = payload.questionIds;
          if (!Array.isArray(ids) || ids.length !== questions.length || new Set(ids).size !== ids.length || ids.some((key) => !questions.some((item) => item.id === key))) fail("invalid-argument", "Provide every question exactly once.");
          questions = ids.map((key, orderIndex) => ({...questions.find((item) => item.id === key), orderIndex}));
        } else if (action === "start") {
          if (quiz.status !== "draft" || !questions.length) fail("failed-precondition", "A draft with questions is required.");
          quiz = openQuestion({...quiz, startedAt: time}, questions, 0, time);
        } else if (action === "pause") {
          if (quiz.status !== "live") fail("failed-precondition", "Quiz is not live.");
          quiz = {...quiz, status: "paused", questionRemainingMs: Math.max(0, quiz.currentQuestionEndsAt - time),
            elapsedBeforeMs: quiz.elapsedBeforeMs + Math.max(0, time - quiz.currentQuestionStartedAt), currentQuestionStartedAt: null};
        } else if (action === "resume") {
          if (quiz.status !== "paused") fail("failed-precondition", "Quiz is not paused.");
          quiz = {...quiz, status: "live", currentQuestionStartedAt: time, currentQuestionEndsAt: time + quiz.questionRemainingMs};
        } else if (action === "next") {
          if (!["live", "paused"].includes(quiz.status)) fail("failed-precondition", "Quiz has not started.");
          quiz = openQuestion(quiz, questions, quiz.currentQuestionIndex + 1, time);
        } else if (action === "end") {
          if (!["live", "paused"].includes(quiz.status)) fail("failed-precondition", "Quiz has not started.");
          quiz = {...quiz, status: "ended", endedAt: time, currentQuestionEndsAt: null};
        } else if (action === "restart") {
          if (quiz.status !== "ended") fail("failed-precondition", "End the current run before restarting.");
          const keep = payload.keepParticipants === true;
          quiz = {...quiz, status: "draft", session: quiz.session + 1, membershipEpoch: quiz.membershipEpoch + (keep ? 0 : 1),
            participantCount: keep ? quiz.participantCount : 0, enrolledCount: keep ? quiz.participantCount : 0,
            startedAt: null, endedAt: null, currentQuestionIndex: null, currentQuestionId: null, currentQuestionStartedAt: null,
            currentQuestionEndsAt: null, totalResponses: 0, correctResponses: 0};
        } else if (action === "delete") {
          quiz = {...quiz, deletedAt: time, status: "ended", endedAt: time};
        } else fail("invalid-argument", "Unsupported quiz action.");
        if (Buffer.byteLength(JSON.stringify(questions)) > 700000) fail("resource-exhausted", "Question set is too large.");
        quiz = {...quiz, totalQuestions: questions.length, revision: quiz.revision + 1};
        const result = {ok: true, quizId: quiz.id, revision: quiz.revision, ...(questionId ? {questionId} : {})};
        tx.set(state.document.ref, quiz);
        tx.set(state.secret.ref, {questions});
        tx.create(operationRef, {fingerprint, result, actorUid: uid, createdAt: time});
        if (action === "addQuestion") tx.create(ref("LiveQuizQuestionLookup", questionId), {quizId: quiz.id});
        if (action === "deleteQuestion") tx.delete(ref("LiveQuizQuestionLookup", questionId));
        if (action === "delete" && state.event.liveQuizId === quiz.id) tx.update(ref("Events", quiz.eventId), {hasLiveQuiz: false, liveQuizId: null});
        return result;
      }
      const participantId = hash(quiz.id, uid);
      if (data.participantId && data.participantId !== participantId) fail("permission-denied", "This participant belongs to another session.");
      const participantRef = ref("QuizParticipants", participantId);
      const participantDoc = await tx.get(participantRef);
      const stored = participantDoc.exists ? participantDoc.data() : null;
      let participant = currentParticipant(stored, quiz);
      if (action === "join") {
        if (quiz.status === "ended") fail("failed-precondition", "The quiz has ended.");
        if ((state.anonymous || payload.isAnonymous === true) && !quiz.allowAnonymous) fail("permission-denied", "This quiz requires a named signed-in participant.");
        if (participant?.isActive) { save(tx, state); return {ok: true, quizId: quiz.id, participantId, revision: quiz.revision}; }
        const alreadyEnrolled = stored?.membershipEpoch === quiz.membershipEpoch && stored.session === quiz.session;
        if (quiz.participantCount >= quiz.maxParticipants || (!alreadyEnrolled && quiz.enrolledCount >= quiz.maxParticipants)) fail("resource-exhausted", "The quiz is full.");
        participant = {...(participant || {}), id: participantId, quizId: quiz.id, userId: uid,
          displayName: text(payload.displayName, 80, true) || `Participant ${participantId.slice(0, 6)}`,
          joinedAt: time, lastActiveAt: time, isAnonymous: state.anonymous || payload.isAnonymous === true, isActive: true,
          currentScore: participant?.currentScore || 0, questionsAnswered: participant?.questionsAnswered || 0, correctAnswers: participant?.correctAnswers || 0,
          membershipEpoch: quiz.membershipEpoch, session: quiz.session, currentRank: null, bestRank: null};
        tx.set(participantRef, participant);
        tx.set(state.document.ref, {...quiz, participantCount: quiz.participantCount + 1, enrolledCount: quiz.enrolledCount + (alreadyEnrolled ? 0 : 1)});
        return {ok: true, quizId: quiz.id, participantId, revision: quiz.revision};
      }
      if (!participant || !stored || stored.userId !== uid) fail("permission-denied", "Join the quiz before participating.");
      if (action === "leave") {
        tx.set(participantRef, {...stored, ...participant, session: participant.isActive ? quiz.session : stored.session,
          userId: uid, isActive: false, lastActiveAt: time});
        tx.set(state.document.ref, {...quiz, participantCount: Math.max(0, quiz.participantCount - (participant.isActive ? 1 : 0))});
        return {ok: true, quizId: quiz.id, participantId, revision: quiz.revision};
      }
      if (action !== "submitAnswer") fail("invalid-argument", "Unsupported quiz action.");
      if (payload.session !== quiz.session) fail("failed-precondition", "This answer belongs to an earlier quiz run.");
      const questionId = id(data.questionId);
      const responseRef = ref("QuizResponses", hash(quiz.id, quiz.session, questionId, participantId));
      const existing = await tx.get(responseRef);
      if (existing.exists) {
        if (JSON.stringify(existing.get("answer")) !== JSON.stringify(payload.answer)) fail("already-exists", "This question already has a different answer.");
        save(tx, state);
        return {ok: true, quizId: quiz.id, participantId, response: visibleResponse(existing.data(), quiz, time), revision: quiz.revision};
      }
      if (!participant.isActive || quiz.status !== "live" || quiz.currentQuestionId !== questionId || time >= quiz.currentQuestionEndsAt) fail("failed-precondition", "This question is closed.");
      const current = questions[quiz.currentQuestionIndex];
      const elapsed = Math.max(0, quiz.elapsedBeforeMs + time - quiz.currentQuestionStartedAt);
      const result = grade(current, payload.answer, elapsed);
      const response = {id: responseRef.id, quizId: quiz.id, questionId, participantId, userId: uid, session: quiz.session,
        questionIndex: quiz.currentQuestionIndex, answer: payload.answer, submittedAt: time, ...result};
      tx.create(responseRef, response);
      tx.set(participantRef, {...stored, ...participant, userId: uid, session: quiz.session, lastActiveAt: time,
        currentScore: participant.currentScore + result.totalPoints, questionsAnswered: participant.questionsAnswered + 1,
        correctAnswers: participant.correctAnswers + (result.isCorrect ? 1 : 0)});
      tx.set(state.document.ref, {...quiz, totalResponses: quiz.totalResponses + 1, correctResponses: quiz.correctResponses + (result.isCorrect ? 1 : 0)});
      return {ok: true, quizId: quiz.id, participantId, response: visibleResponse(response, quiz, time), revision: quiz.revision};
    });
  }

  async function read(request) {
    actor(request);
    return db.runTransaction(async (tx) => {
      const time = now();
      const state = await load(tx, request, time);
      if (!state) return {data: null, serverTime: time};
      const {quiz, questions, uid, host} = state;
      const input = request.data || {};
      const selfId = hash(quiz.id, uid);
      let data;
      if (["quiz", "getByEvent"].includes(input.action)) {
        const visible = {...quiz};
        delete visible.createFingerprint;
        if (!host) { delete visible.correctResponses; delete visible.totalResponses; }
        data = {...visible, canManage: host};
      } else if (input.action === "questions") {
        data = (host ? questions : questions.filter((item) => item.orderIndex <= (quiz.currentQuestionIndex ?? -1)).map(publicQuestion))
            .map((item) => ({...item, session: quiz.session}));
      } else if (input.action === "currentQuestion") {
        const current = questions.find((item) => item.id === quiz.currentQuestionId);
        data = current ? {...(host ? current : publicQuestion(current)), session: quiz.session} : null;
      } else if (["participant", "participants"].includes(input.action)) {
        if (input.action === "participant") {
          const key = input.participantId || selfId;
          if (!host && key !== selfId) fail("permission-denied", "Only your participant details are available.");
          const document = await tx.get(ref("QuizParticipants", id(key)));
          if (document.exists && document.get("quizId") !== quiz.id) fail("permission-denied", "Participant belongs to another quiz.");
          data = currentParticipant(document.data(), quiz);
          if (data && !host && questionOpen(quiz, quiz.currentQuestionId, time)) {
            const pending = await tx.get(ref("QuizResponses", hash(quiz.id, quiz.session, quiz.currentQuestionId, key)));
            data = visibleParticipant(data, pending.data());
          }
        } else {
          const snapshot = await tx.get(db.collection("QuizParticipants").where("quizId", "==", quiz.id).where("membershipEpoch", "==", quiz.membershipEpoch).where("isActive", "==", true).limit(1001));
          let rows = snapshot.docs.map((doc) => currentParticipant(doc.data(), quiz)).filter((item) => item?.isActive);
          if (!host && questionOpen(quiz, quiz.currentQuestionId, time)) {
            const pending = await tx.get(db.collection("QuizResponses").where("quizId", "==", quiz.id).where("session", "==", quiz.session).where("questionId", "==", quiz.currentQuestionId).limit(1001));
            const answers = new Map(pending.docs.map((doc) => [doc.get("participantId"), doc.data()]));
            rows = rows.map((item) => visibleParticipant(item, answers.get(item.id)));
          }
          rows.sort((a, b) => b.currentScore - a.currentScore || a.joinedAt - b.joinedAt || a.id.localeCompare(b.id));
          data = rows.map((item, index) => ({...item, currentRank: index + 1}));
          if (!host && !quiz.showLeaderboard) data = data.filter((item) => item.id === selfId);
        }
      } else if (input.action === "participantResponse") {
        const participantId = input.participantId || selfId;
        if (!host && participantId !== selfId) fail("permission-denied", "Only your answers are available.");
        const document = await tx.get(ref("QuizResponses", hash(quiz.id, quiz.session, id(input.questionId), participantId)));
        data = document.exists ? visibleResponse(document.data(), quiz, time, host) : null;
      } else if (input.action === "questionResponses") {
        if (!host) fail("permission-denied", "Only the host can review all answers.");
        const snapshot = await tx.get(db.collection("QuizResponses").where("quizId", "==", quiz.id).where("session", "==", quiz.session).where("questionId", "==", id(input.questionId)).limit(1001));
        data = snapshot.docs.map((doc) => visibleResponse(doc.data(), quiz, time, host));
      } else if (input.action === "stats") {
        if (!host) fail("permission-denied", "Only the host can review quiz statistics.");
        data = {totalParticipants: quiz.enrolledCount, activeParticipants: quiz.participantCount,
          totalResponses: quiz.totalResponses, correctResponses: quiz.correctResponses,
          averageAccuracy: quiz.totalResponses ? quiz.correctResponses * 100 / quiz.totalResponses : 0,
          questionsAsked: quiz.currentQuestionIndex === null ? 0 : quiz.currentQuestionIndex + 1,
          totalQuestions: quiz.totalQuestions, progress: quiz.totalQuestions ? ((quiz.currentQuestionIndex ?? -1) + 1) * 100 / quiz.totalQuestions : 0};
      } else fail("invalid-argument", "Unsupported quiz read.");
      save(tx, state);
      return {data, serverTime: time};
    });
  }
  return {mutation, read};
}

function createLiveQuizFunctions(admin) {
  const handlers = createQuizHandlers(admin.firestore());
  const options = {region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true", timeoutSeconds: 60, maxInstances: 40};
  return {quizMutationV1: onCall(options, handlers.mutation), quizReadV1: onCall(options, handlers.read)};
}

module.exports = {createLiveQuizFunctions, createQuizHandlers, question, settings, advance, grade, publicQuestion, currentParticipant, visibleResponse};
