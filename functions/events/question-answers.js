"use strict";

const {HttpsError} = require("firebase-functions/v2/https");

function answerMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function normalizeAnswer(question, value) {
  if (question.type === "multiple_choice") {
    const allowed = new Set(question.options || []);
    const items = [...new Set((Array.isArray(value) ? value : [])
        .map(String).map((item) => item.trim()).filter((item) => allowed.has(item)))];
    if (question.required && items.length === 0) {
      throw new HttpsError("invalid-argument", `Answer “${question.prompt}”.`);
    }
    return items;
  }
  if (question.type === "acknowledgement") {
    if (question.required && value !== true) {
      throw new HttpsError("invalid-argument", `Acknowledge “${question.prompt}”.`);
    }
    return value === true;
  }
  const normalized = typeof value === "string" ? value.trim().slice(0, 4000) : "";
  if (question.type === "single_choice" && normalized &&
      !(question.options || []).includes(normalized)) {
    throw new HttpsError("invalid-argument", "Choose a valid answer option.");
  }
  if (question.required && !normalized) {
    throw new HttpsError("invalid-argument", `Answer “${question.prompt}”.`);
  }
  return normalized;
}

async function registrationAnswers(eventRef, submitted) {
  const snapshot = await eventRef.collection("EventQuestions")
      .where("timing", "==", "registration").get();
  const supplied = answerMap(submitted);
  return snapshot.docs.sort((a, b) => Number(a.get("order") || 0) - Number(b.get("order") || 0))
      .map((document) => {
        const question = {id: document.id, ...document.data()};
        return {questionId: document.id, prompt: String(question.prompt || question.questionTitle || ""),
          type: question.type || "long_text", version: Number(question.version || 2),
          answer: normalizeAnswer(question, supplied[document.id])};
      });
}

module.exports = {normalizeAnswer, registrationAnswers};
