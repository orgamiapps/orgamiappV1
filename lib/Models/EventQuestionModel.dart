class EventQuestionModel {
  static String firebaseKey = 'EventQuestions';

  String id, questionTitle;
  String? answer;

  bool required;

  EventQuestionModel({
    required this.id,
    required this.questionTitle,
    this.answer,
    required this.required,
  });

  factory EventQuestionModel.fromJson(parsedJson) {
    return EventQuestionModel(
      id: parsedJson['id'],
      questionTitle: parsedJson['questionTitle'],
      answer: parsedJson['answer'],
      required: parsedJson['required'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};

    data['id'] = id;
    data['questionTitle'] = questionTitle;
    data['answer'] = answer;
    data['required'] = required;

    return data;
  }
}
