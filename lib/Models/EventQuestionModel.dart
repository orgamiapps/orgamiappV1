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

  factory EventQuestionModel.fromJson(dynamic parsedJson) {
    // Support both DocumentSnapshot and Map
    final data = parsedJson is Map
        ? parsedJson
        : (parsedJson.data() as Map<String, dynamic>);

    return EventQuestionModel(
      id: data['id'],
      questionTitle: data['questionTitle'],
      answer: data['answer'],
      required: data['required'],
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
