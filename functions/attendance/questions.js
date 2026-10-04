"use strict";

function mergeAttendanceAnswers(registrationAnswers, checkInAnswers) {
  // V3 registration answers are structured records; legacy check-in answers
  // are title-delimited strings. Retain the structured records unchanged.
  const answers = Array.isArray(registrationAnswers) ? [...registrationAnswers] : [];
  for (const answer of checkInAnswers) {
    const title = answer.split("--ans--")[0];
    const index = answers.findIndex((item) => typeof item === "string" && item.split("--ans--")[0] === title);
    if (index >= 0) answers[index] = answer; else answers.push(answer);
  }
  return answers;
}

function requiredCheckInQuestions(documents, answers = []) {
  const submitted = Array.isArray(answers) ? answers.filter((answer) => typeof answer === "string") : [];
  return documents.map((document) => document.data()).filter((question) =>
    question.required && (question.timing || "check_in") === "check_in").map((question) => ({
    ...question, title: String(question.prompt || question.questionTitle || "").trim(),
  })).filter((question) => !question.title || !submitted.some((answer) =>
    answer.startsWith(`${question.title}--ans--`) && answer.slice(question.title.length + 7).trim()));
}

module.exports = {requiredCheckInQuestions, mergeAttendanceAnswers};
