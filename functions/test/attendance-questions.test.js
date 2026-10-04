"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {requiredCheckInQuestions, mergeAttendanceAnswers} = require("../attendance/questions");
const docs = (...values) => values.map((value) => ({data: () => value}));
test("registration-only required questions do not block admission", () => {
  assert.deepEqual(requiredCheckInQuestions(docs({timing: "registration", required: true, prompt: "Diet"})), []);
});
test("check-in uses current prompt and legacy title/default timing", () => {
  const questions = docs({timing: "check_in", required: true, prompt: "Badge"}, {required: true, questionTitle: "Name"});
  assert.equal(requiredCheckInQuestions(questions, ["Badge--ans--B", "Name--ans--N"]).length, 0);
  assert.deepEqual(requiredCheckInQuestions(questions, ["Badge--ans--  "]).map((q) => q.title), ["Badge", "Name"]);
});

test("structured V3 registration answers survive legacy door-answer merge", () => {
  const registration = {questionId: "access", prompt: "Accessibility needs", type: "short_text", answer: "Step-free"};
  const existing = [registration, "Door code--ans--old"];
  const merged = mergeAttendanceAnswers(existing, ["Door code--ans--new"]);
  assert.deepEqual(merged, [registration, "Door code--ans--new"]);
  assert.deepEqual(existing, [registration, "Door code--ans--old"]);
  assert.deepEqual(requiredCheckInQuestions(docs({timing: "registration", required: true, prompt: "Accessibility needs"},
      {required: true, questionTitle: "Door code"}), merged), []);
});
