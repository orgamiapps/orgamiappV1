import 'package:cloud_firestore/cloud_firestore.dart';

enum QuestionType { multipleChoice, trueFalse, shortAnswer }

class QuizQuestionModel {
  static String firebaseKey = 'QuizQuestions';

  final String id;
  final String quizId;
  final int orderIndex;
  final QuestionType type;
  final String question;
  final String? imageUrl;
  
  // Multiple Choice & True/False
  final List<String> options;
  final int? correctOptionIndex; // For multiple choice and true/false
  
  // Short Answer
  final List<String> acceptableAnswers; // For short answer questions
  final bool caseSensitive;
  
  // Settings
  final int timeLimit; // seconds, overrides quiz default if set
  final int points;
  final String? explanation; // Shown after answering
  
  const QuizQuestionModel({
    required this.id,
    required this.quizId,
    required this.orderIndex,
    required this.type,
    required this.question,
    this.imageUrl,
    this.options = const [],
    this.correctOptionIndex,
    this.acceptableAnswers = const [],
    this.caseSensitive = false,
    this.timeLimit = 30,
    this.points = 100,
    this.explanation,
  });

  factory QuizQuestionModel.fromJson(Map<String, dynamic> data) {
    return QuizQuestionModel(
      id: data['id'] ?? '',
      quizId: data['quizId'] ?? '',
      orderIndex: data['orderIndex'] ?? 0,
      type: QuestionType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => QuestionType.multipleChoice,
      ),
      question: data['question'] ?? '',
      imageUrl: data['imageUrl'],
      options: data['options'] != null ? List<String>.from(data['options']) : [],
      correctOptionIndex: data['correctOptionIndex'],
      acceptableAnswers: data['acceptableAnswers'] != null 
          ? List<String>.from(data['acceptableAnswers']) 
          : [],
      caseSensitive: data['caseSensitive'] ?? false,
      timeLimit: data['timeLimit'] ?? 30,
      points: data['points'] ?? 100,
      explanation: data['explanation'],
    );
  }

  factory QuizQuestionModel.fromFirestore(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>;
    return QuizQuestionModel.fromJson({...data, 'id': snap.id});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quizId': quizId,
      'orderIndex': orderIndex,
      'type': type.name,
      'question': question,
      'imageUrl': imageUrl,
      'options': options,
      'correctOptionIndex': correctOptionIndex,
      'acceptableAnswers': acceptableAnswers,
      'caseSensitive': caseSensitive,
      'timeLimit': timeLimit,
      'points': points,
      'explanation': explanation,
    };
  }

  QuizQuestionModel copyWith({
    String? id,
    String? quizId,
    int? orderIndex,
    QuestionType? type,
    String? question,
    String? imageUrl,
    List<String>? options,
    int? correctOptionIndex,
    List<String>? acceptableAnswers,
    bool? caseSensitive,
    int? timeLimit,
    int? points,
    String? explanation,
  }) {
    return QuizQuestionModel(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      orderIndex: orderIndex ?? this.orderIndex,
      type: type ?? this.type,
      question: question ?? this.question,
      imageUrl: imageUrl ?? this.imageUrl,
      options: options ?? this.options,
      correctOptionIndex: correctOptionIndex ?? this.correctOptionIndex,
      acceptableAnswers: acceptableAnswers ?? this.acceptableAnswers,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      timeLimit: timeLimit ?? this.timeLimit,
      points: points ?? this.points,
      explanation: explanation ?? this.explanation,
    );
  }

  // Helper methods
  bool get isMultipleChoice => type == QuestionType.multipleChoice;
  bool get isTrueFalse => type == QuestionType.trueFalse;
  bool get isShortAnswer => type == QuestionType.shortAnswer;
  
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasExplanation => explanation != null && explanation!.isNotEmpty;
  
  String get typeDisplayName {
    switch (type) {
      case QuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuestionType.trueFalse:
        return 'True/False';
      case QuestionType.shortAnswer:
        return 'Short Answer';
    }
  }
  
  // Validation
  bool get isValid {
    if (question.trim().isEmpty) return false;
    
    switch (type) {
      case QuestionType.multipleChoice:
        return options.length >= 2 && 
               correctOptionIndex != null && 
               correctOptionIndex! >= 0 && 
               correctOptionIndex! < options.length;
               
      case QuestionType.trueFalse:
        return correctOptionIndex != null && 
               (correctOptionIndex == 0 || correctOptionIndex == 1);
               
      case QuestionType.shortAnswer:
        return acceptableAnswers.isNotEmpty;
    }
  }
  
  // Answer checking
  bool isAnswerCorrect(dynamic answer) {
    switch (type) {
      case QuestionType.multipleChoice:
      case QuestionType.trueFalse:
        if (answer is int) {
          return answer == correctOptionIndex;
        }
        return false;
        
      case QuestionType.shortAnswer:
        if (answer is String) {
          final userAnswer = caseSensitive ? answer : answer.toLowerCase();
          return acceptableAnswers.any((acceptable) {
            final target = caseSensitive ? acceptable : acceptable.toLowerCase();
            return target == userAnswer;
          });
        }
        return false;
    }
  }
  
  // For short answer questions, return similarity score
  double getAnswerSimilarity(String userAnswer) {
    if (type != QuestionType.shortAnswer) return 0.0;
    
    final cleanUserAnswer = caseSensitive ? userAnswer.trim() : userAnswer.trim().toLowerCase();
    
    double maxSimilarity = 0.0;
    for (final acceptable in acceptableAnswers) {
      final cleanAcceptable = caseSensitive ? acceptable.trim() : acceptable.trim().toLowerCase();
      
      // Simple similarity calculation (can be enhanced)
      if (cleanAcceptable == cleanUserAnswer) {
        return 1.0;
      } else if (cleanAcceptable.contains(cleanUserAnswer) || cleanUserAnswer.contains(cleanAcceptable)) {
        final similarity = cleanUserAnswer.length / cleanAcceptable.length;
        maxSimilarity = similarity > maxSimilarity ? similarity : maxSimilarity;
      }
    }
    
    return maxSimilarity;
  }

  // Factory methods for creating different question types
  factory QuizQuestionModel.multipleChoice({
    required String id,
    required String quizId,
    required int orderIndex,
    required String question,
    required List<String> options,
    required int correctOptionIndex,
    String? imageUrl,
    String? explanation,
    int timeLimit = 30,
    int points = 100,
  }) {
    return QuizQuestionModel(
      id: id,
      quizId: quizId,
      orderIndex: orderIndex,
      type: QuestionType.multipleChoice,
      question: question,
      imageUrl: imageUrl,
      options: options,
      correctOptionIndex: correctOptionIndex,
      explanation: explanation,
      timeLimit: timeLimit,
      points: points,
    );
  }

  factory QuizQuestionModel.trueFalse({
    required String id,
    required String quizId,
    required int orderIndex,
    required String question,
    required bool correctAnswer,
    String? imageUrl,
    String? explanation,
    int timeLimit = 30,
    int points = 100,
  }) {
    return QuizQuestionModel(
      id: id,
      quizId: quizId,
      orderIndex: orderIndex,
      type: QuestionType.trueFalse,
      question: question,
      imageUrl: imageUrl,
      options: const ['True', 'False'],
      correctOptionIndex: correctAnswer ? 0 : 1,
      explanation: explanation,
      timeLimit: timeLimit,
      points: points,
    );
  }

  factory QuizQuestionModel.shortAnswer({
    required String id,
    required String quizId,
    required int orderIndex,
    required String question,
    required List<String> acceptableAnswers,
    bool caseSensitive = false,
    String? imageUrl,
    String? explanation,
    int timeLimit = 30,
    int points = 100,
  }) {
    return QuizQuestionModel(
      id: id,
      quizId: quizId,
      orderIndex: orderIndex,
      type: QuestionType.shortAnswer,
      question: question,
      imageUrl: imageUrl,
      acceptableAnswers: acceptableAnswers,
      caseSensitive: caseSensitive,
      explanation: explanation,
      timeLimit: timeLimit,
      points: points,
    );
  }
}
