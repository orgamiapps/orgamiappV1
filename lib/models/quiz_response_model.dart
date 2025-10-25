import 'package:cloud_firestore/cloud_firestore.dart';

class QuizResponseModel {
  static String firebaseKey = 'QuizResponses';

  final String id;
  final String quizId;
  final String questionId;
  final String participantId;
  final int questionIndex;
  
  // Answer data
  final dynamic answer; // int for multiple choice/true-false, String for short answer
  final DateTime submittedAt;
  final int timeToAnswer; // milliseconds taken to answer
  
  // Scoring
  final bool isCorrect;
  final int pointsEarned;
  final double? similarityScore; // for short answer questions
  
  // Metadata
  final bool isLate; // submitted after time limit
  final int questionTimeLimit; // time limit for this question
  
  const QuizResponseModel({
    required this.id,
    required this.quizId,
    required this.questionId,
    required this.participantId,
    required this.questionIndex,
    required this.answer,
    required this.submittedAt,
    required this.timeToAnswer,
    required this.isCorrect,
    required this.pointsEarned,
    this.similarityScore,
    this.isLate = false,
    required this.questionTimeLimit,
  });

  factory QuizResponseModel.fromJson(Map<String, dynamic> data) {
    return QuizResponseModel(
      id: data['id'] ?? '',
      quizId: data['quizId'] ?? '',
      questionId: data['questionId'] ?? '',
      participantId: data['participantId'] ?? '',
      questionIndex: data['questionIndex'] ?? 0,
      answer: data['answer'],
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      timeToAnswer: data['timeToAnswer'] ?? 0,
      isCorrect: data['isCorrect'] ?? false,
      pointsEarned: data['pointsEarned'] ?? 0,
      similarityScore: (data['similarityScore'] as num?)?.toDouble(),
      isLate: data['isLate'] ?? false,
      questionTimeLimit: data['questionTimeLimit'] ?? 30,
    );
  }

  factory QuizResponseModel.fromFirestore(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>;
    return QuizResponseModel.fromJson({...data, 'id': snap.id});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quizId': quizId,
      'questionId': questionId,
      'participantId': participantId,
      'questionIndex': questionIndex,
      'answer': answer,
      'submittedAt': Timestamp.fromDate(submittedAt),
      'timeToAnswer': timeToAnswer,
      'isCorrect': isCorrect,
      'pointsEarned': pointsEarned,
      'similarityScore': similarityScore,
      'isLate': isLate,
      'questionTimeLimit': questionTimeLimit,
    };
  }

  QuizResponseModel copyWith({
    String? id,
    String? quizId,
    String? questionId,
    String? participantId,
    int? questionIndex,
    dynamic answer,
    DateTime? submittedAt,
    int? timeToAnswer,
    bool? isCorrect,
    int? pointsEarned,
    double? similarityScore,
    bool? isLate,
    int? questionTimeLimit,
  }) {
    return QuizResponseModel(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      questionId: questionId ?? this.questionId,
      participantId: participantId ?? this.participantId,
      questionIndex: questionIndex ?? this.questionIndex,
      answer: answer ?? this.answer,
      submittedAt: submittedAt ?? this.submittedAt,
      timeToAnswer: timeToAnswer ?? this.timeToAnswer,
      isCorrect: isCorrect ?? this.isCorrect,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      similarityScore: similarityScore ?? this.similarityScore,
      isLate: isLate ?? this.isLate,
      questionTimeLimit: questionTimeLimit ?? this.questionTimeLimit,
    );
  }

  // Helper methods
  String get answerDisplay {
    if (answer is int) {
      return answer.toString();
    } else if (answer is String) {
      return answer as String;
    }
    return 'No answer';
  }
  
  String get timeToAnswerDisplay {
    final seconds = timeToAnswer / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }
  
  double get responseTimePercentage {
    if (questionTimeLimit <= 0) return 0.0;
    final responseTimeSeconds = timeToAnswer / 1000;
    return (responseTimeSeconds / questionTimeLimit).clamp(0.0, 1.0);
  }
  
  String get speedBonus {
    final percentage = responseTimePercentage;
    if (percentage <= 0.25) return 'Lightning Fast!';
    if (percentage <= 0.50) return 'Quick Response';
    if (percentage <= 0.75) return 'Good Timing';
    return 'Just in Time';
  }
  
  // Calculate bonus points based on response speed (if correct)
  int get speedBonusPoints {
    if (!isCorrect) return 0;
    
    final percentage = responseTimePercentage;
    if (percentage <= 0.25) return (pointsEarned * 0.5).round(); // 50% bonus
    if (percentage <= 0.50) return (pointsEarned * 0.3).round(); // 30% bonus  
    if (percentage <= 0.75) return (pointsEarned * 0.1).round(); // 10% bonus
    return 0; // No bonus
  }
  
  int get totalPoints => pointsEarned + speedBonusPoints;
  
  // Factory method for creating a response
  factory QuizResponseModel.create({
    required String quizId,
    required String questionId,
    required String participantId,
    required int questionIndex,
    required dynamic answer,
    required bool isCorrect,
    required int basePoints,
    required int timeToAnswer,
    required int questionTimeLimit,
    double? similarityScore,
  }) {
    final submittedAt = DateTime.now();
    final isLate = timeToAnswer > (questionTimeLimit * 1000);
    
    // Calculate points with potential penalty for late submission
    int pointsEarned = isCorrect ? basePoints : 0;
    if (isLate && isCorrect) {
      pointsEarned = (pointsEarned * 0.5).round(); // 50% penalty for late correct answers
    }
    
    return QuizResponseModel(
      id: '', // Will be set by Firestore
      quizId: quizId,
      questionId: questionId,
      participantId: participantId,
      questionIndex: questionIndex,
      answer: answer,
      submittedAt: submittedAt,
      timeToAnswer: timeToAnswer,
      isCorrect: isCorrect,
      pointsEarned: pointsEarned,
      similarityScore: similarityScore,
      isLate: isLate,
      questionTimeLimit: questionTimeLimit,
    );
  }
}

// Model for aggregated response statistics
class QuestionResponseStats {
  final String questionId;
  final int totalResponses;
  final int correctResponses;
  final Map<String, int> answerDistribution; // answer -> count
  final double averageResponseTime;
  final double accuracyPercentage;
  
  const QuestionResponseStats({
    required this.questionId,
    required this.totalResponses,
    required this.correctResponses,
    required this.answerDistribution,
    required this.averageResponseTime,
    required this.accuracyPercentage,
  });
  
  factory QuestionResponseStats.fromResponses(String questionId, List<QuizResponseModel> responses) {
    if (responses.isEmpty) {
      return QuestionResponseStats(
        questionId: questionId,
        totalResponses: 0,
        correctResponses: 0,
        answerDistribution: {},
        averageResponseTime: 0.0,
        accuracyPercentage: 0.0,
      );
    }
    
    final correctCount = responses.where((r) => r.isCorrect).length;
    final averageTime = responses
        .map((r) => r.timeToAnswer)
        .reduce((a, b) => a + b) / responses.length / 1000; // Convert to seconds
    
    final distribution = <String, int>{};
    for (final response in responses) {
      final answerKey = response.answerDisplay;
      distribution[answerKey] = (distribution[answerKey] ?? 0) + 1;
    }
    
    return QuestionResponseStats(
      questionId: questionId,
      totalResponses: responses.length,
      correctResponses: correctCount,
      answerDistribution: distribution,
      averageResponseTime: averageTime,
      accuracyPercentage: responses.isEmpty ? 0.0 : (correctCount / responses.length) * 100,
    );
  }
  
  String get accuracyDisplay => '${accuracyPercentage.toStringAsFixed(1)}%';
  String get averageTimeDisplay => '${averageResponseTime.toStringAsFixed(1)}s';
}
