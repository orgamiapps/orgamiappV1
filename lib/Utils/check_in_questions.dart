/// The server treats legacy questions without timing as door questions.
bool isRequiredCheckInQuestion(Map question) =>
    (question['timing'] ?? 'check_in') == 'check_in' &&
    question['required'] != null &&
    question['required'] != false &&
    question['required'] != 0 &&
    question['required'] != '';

String checkInQuestionTitle(Map question) {
  final prompt = question['prompt']?.toString().trim() ?? '';
  return prompt.isNotEmpty
      ? prompt
      : (question['questionTitle']?.toString().trim() ?? '');
}

bool hasCheckInAnswer(Map question, Iterable answers) {
  final title = checkInQuestionTitle(question);
  if (title.isEmpty) return false;
  final prefix = '$title--ans--';
  // Structured registration answers cannot satisfy a separate door question.
  return answers.whereType<String>().any(
    (answer) =>
        answer.startsWith(prefix) &&
        answer.substring(prefix.length).trim().isNotEmpty,
  );
}
