import 'package:cloud_firestore/cloud_firestore.dart';

class QuizParticipantModel {
  static String firebaseKey = 'QuizParticipants';

  final String id;
  final String quizId;
  final String? userId; // null for anonymous participants
  final String displayName;
  final DateTime joinedAt;
  final bool isAnonymous;
  
  // Current status
  final int currentScore;
  final int questionsAnswered;
  final int correctAnswers;
  final bool isActive; // still participating
  final DateTime lastActiveAt;
  
  // Rankings
  final int? currentRank;
  final int? bestRank; // highest rank achieved during quiz
  
  const QuizParticipantModel({
    required this.id,
    required this.quizId,
    this.userId,
    required this.displayName,
    required this.joinedAt,
    this.isAnonymous = true,
    this.currentScore = 0,
    this.questionsAnswered = 0,
    this.correctAnswers = 0,
    this.isActive = true,
    required this.lastActiveAt,
    this.currentRank,
    this.bestRank,
  });

  factory QuizParticipantModel.fromJson(Map<String, dynamic> data) {
    return QuizParticipantModel(
      id: data['id'] ?? '',
      quizId: data['quizId'] ?? '',
      userId: data['userId'],
      displayName: data['displayName'] ?? '',
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isAnonymous: data['isAnonymous'] ?? true,
      currentScore: data['currentScore'] ?? 0,
      questionsAnswered: data['questionsAnswered'] ?? 0,
      correctAnswers: data['correctAnswers'] ?? 0,
      isActive: data['isActive'] ?? true,
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      currentRank: data['currentRank'],
      bestRank: data['bestRank'],
    );
  }

  factory QuizParticipantModel.fromFirestore(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>;
    return QuizParticipantModel.fromJson({...data, 'id': snap.id});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quizId': quizId,
      'userId': userId,
      'displayName': displayName,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'isAnonymous': isAnonymous,
      'currentScore': currentScore,
      'questionsAnswered': questionsAnswered,
      'correctAnswers': correctAnswers,
      'isActive': isActive,
      'lastActiveAt': Timestamp.fromDate(lastActiveAt),
      'currentRank': currentRank,
      'bestRank': bestRank,
    };
  }

  QuizParticipantModel copyWith({
    String? id,
    String? quizId,
    String? userId,
    String? displayName,
    DateTime? joinedAt,
    bool? isAnonymous,
    int? currentScore,
    int? questionsAnswered,
    int? correctAnswers,
    bool? isActive,
    DateTime? lastActiveAt,
    int? currentRank,
    int? bestRank,
  }) {
    return QuizParticipantModel(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      joinedAt: joinedAt ?? this.joinedAt,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      currentScore: currentScore ?? this.currentScore,
      questionsAnswered: questionsAnswered ?? this.questionsAnswered,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      isActive: isActive ?? this.isActive,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      currentRank: currentRank ?? this.currentRank,
      bestRank: bestRank ?? this.bestRank,
    );
  }

  // Helper methods
  double get accuracyPercentage {
    if (questionsAnswered == 0) return 0.0;
    return (correctAnswers / questionsAnswered) * 100;
  }
  
  String get accuracyDisplay {
    return '${accuracyPercentage.toStringAsFixed(1)}%';
  }
  
  bool get hasAnsweredQuestions => questionsAnswered > 0;
  
  String get rankDisplay {
    if (currentRank == null) return 'Unranked';
    return _getRankSuffix(currentRank!);
  }
  
  String get bestRankDisplay {
    if (bestRank == null) return 'N/A';
    return _getRankSuffix(bestRank!);
  }
  
  String _getRankSuffix(int rank) {
    if (rank % 100 >= 11 && rank % 100 <= 13) {
      return '${rank}th';
    }
    switch (rank % 10) {
      case 1:
        return '${rank}st';
      case 2:
        return '${rank}nd';
      case 3:
        return '${rank}rd';
      default:
        return '${rank}th';
    }
  }
  
  // Factory method for creating anonymous participants
  factory QuizParticipantModel.anonymous({
    required String quizId,
    String? customDisplayName,
  }) {
    final anonymousNames = [
      'Quiz Master', 'Brain Teaser', 'Smart Cookie', 'Trivia King',
      'Quiz Wizard', 'Know-It-All', 'Curious Cat', 'Fact Finder',
      'Quiz Champion', 'Bright Mind', 'Sharp Thinker', 'Clever Clogs',
      'Quiz Hero', 'Mental Giant', 'Quick Wit', 'Brainy Bunch'
    ];
    
    final randomName = customDisplayName ?? 
        '${anonymousNames[DateTime.now().millisecondsSinceEpoch % anonymousNames.length]} ${DateTime.now().millisecondsSinceEpoch % 9999}';
    
    return QuizParticipantModel(
      id: '', // Will be set by Firestore
      quizId: quizId,
      displayName: randomName,
      joinedAt: DateTime.now(),
      isAnonymous: true,
      lastActiveAt: DateTime.now(),
    );
  }
  
  // Factory method for authenticated participants
  factory QuizParticipantModel.authenticated({
    required String quizId,
    required String userId,
    required String displayName,
  }) {
    return QuizParticipantModel(
      id: '', // Will be set by Firestore
      quizId: quizId,
      userId: userId,
      displayName: displayName,
      joinedAt: DateTime.now(),
      isAnonymous: false,
      lastActiveAt: DateTime.now(),
    );
  }
}
