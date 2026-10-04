class EventQuestionModel {
  static String firebaseKey = 'EventQuestions';

  String id, questionTitle;
  String? answer;

  bool required;
  String type;
  String timing;
  List<String> options;
  int order;
  int version;

  EventQuestionModel({
    required this.id,
    required this.questionTitle,
    this.answer,
    required this.required,
    this.type = 'long_text',
    this.timing = 'check_in',
    this.options = const [],
    this.order = 0,
    this.version = 2,
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
      type: data['type']?.toString() ?? 'long_text',
      timing: data['timing']?.toString() ?? 'check_in',
      options: data['options'] is List
          ? List<String>.from(data['options'])
          : const [],
      order: (data['order'] as num?)?.round() ?? 0,
      version: (data['version'] as num?)?.round() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};

    data['id'] = id;
    data['questionTitle'] = questionTitle;
    data['answer'] = answer;
    data['required'] = required;
    data['type'] = type;
    data['timing'] = timing;
    data['options'] = options;
    data['order'] = order;
    data['version'] = version;

    return data;
  }
}
