"use strict";

// Called only by the account deletion worker, after its deletion guard exists.
// Every commit remains fenced by that worker's lease. Shared quiz content and
// organizer-operation markers require explicit ownership/retention disposition.
async function cleanupQuizAccountData(db, uid, counts) {
  const clean = async (collection, counter, adjust, field = "userId", value = uid) => {
    let page = await db.collection(collection).where(field, "==", value).limit(100).get();
    while (!page.empty) {
      // Older responses only carried participantId. Remove these while the
      // durable owner-to-participant link still exists, so interruption retries
      // can recover the same work without losing its provenance.
      if (collection === "QuizParticipants") for (const participant of page.docs) {
        await clean("QuizResponses", "quizResponsesDeleted", adjustResponses, "participantId", participant.id);
      }
      const removed = await counts.lease.transaction(async (tx) => {
        const current = await Promise.all(page.docs.map((document) => tx.get(document.ref)));
        const owned = current.filter((document) => document.exists && document.get(field) === value);
        if (field === "participantId" && owned.some((document) => document.get("userId") && document.get("userId") !== uid)) {
          const error = new Error("Quiz answer ownership conflicts with its participant; review is required.");
          error.code = "deletion/review-required";
          error.categories = ["quiz:response_ownership"];
          throw error;
        }
        const quizIds = [...new Set(owned.map((document) => document.get("quizId")))];
        const quizzes = await Promise.all(quizIds.map((quizId) => tx.get(db.collection("LiveQuizzes").doc(quizId))));
        for (const quiz of quizzes) {
          if (!quiz.exists) continue;
          const data = quiz.data();
          const records = owned.filter((document) => document.get("quizId") === quiz.id).map((document) => document.data());
          const update = adjust(data, records);
          if (Object.keys(update).length) tx.update(quiz.ref, update);
        }
        for (const document of owned) tx.delete(document.ref);
        tx.set(counts.job, {partialCounts: {...counts, [counter]: (counts[counter] || 0) + owned.length},
          lastCompletedItem: page.docs.at(-1).ref.path}, {merge: true});
        return owned.length;
      });
      counts[counter] = (counts[counter] || 0) + removed;
      page = await db.collection(collection).where(field, "==", value).limit(100).get();
    }
  };
  const adjustResponses = (quiz, records) => {
    const current = records.filter((record) => record.session === quiz.session);
    return current.length ? {totalResponses: Math.max(0, (quiz.totalResponses || 0) - current.length),
      correctResponses: Math.max(0, (quiz.correctResponses || 0) - current.filter((record) => record.isCorrect).length)} : {};
  };
  await clean("QuizResponses", "quizResponsesDeleted", adjustResponses);
  await clean("QuizParticipants", "quizParticipantsDeleted", (quiz, records) => {
    const members = records.filter((record) => record.membershipEpoch === quiz.membershipEpoch);
    const enrolled = members.filter((record) => record.isActive || record.session === quiz.session);
    return members.length ? {participantCount: Math.max(0, (quiz.participantCount || 0) - members.filter((record) => record.isActive).length),
      enrolledCount: Math.max(0, (quiz.enrolledCount || 0) - enrolled.length)} : {};
  });
}

module.exports = {cleanupQuizAccountData};
