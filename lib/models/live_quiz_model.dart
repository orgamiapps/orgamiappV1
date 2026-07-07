import 'package:cloud_firestore/cloud_firestore.dart';

enum QuizStatus { draft, live, paused, ended }

class LiveQuizModel {
  static String firebaseKey = 'LiveQuizzes';

  final String id;
  final String eventId;
  final String creatorId;
  final String title;
  final String? description;
  final QuizStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  
  // Quiz Settings
  final int timePerQuestion; // seconds
  final bool autoAdvance;
  final bool showLeaderboard;
  final bool allowAnonymous;
  final int maxParticipants;
  
  // Current State
  final int? currentQuestionIndex;
  final DateTime? currentQuestionStartedAt;
  final int totalQuestions;
  final int participantCount;

  const LiveQuizModel({
    required this.id,
    required this.eventId,
    required this.creatorId,
    required this.title,
    this.description,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.timePerQuestion = 30,
    this.autoAdvance = true,
    this.showLeaderboard = true,
    this.allowAnonymous = true,
    this.maxParticipants = 1000,
    this.currentQuestionIndex,
    this.currentQuestionStartedAt,
    this.totalQuestions = 0,
    this.participantCount = 0,
  });

  factory LiveQuizModel.fromJson(Map<String, dynamic> data) {
    return LiveQuizModel(
      id: data['id'] ?? '',
      eventId: data['eventId'] ?? '',
      creatorId: data['creatorId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'],
      status: QuizStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => QuizStatus.draft,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      timePerQuestion: data['timePerQuestion'] ?? 30,
      autoAdvance: data['autoAdvance'] ?? true,
      showLeaderboard: data['showLeaderboard'] ?? true,
      allowAnonymous: data['allowAnonymous'] ?? true,
      maxParticipants: data['maxParticipants'] ?? 1000,
      currentQuestionIndex: data['currentQuestionIndex'],
      currentQuestionStartedAt: (data['currentQuestionStartedAt'] as Timestamp?)?.toDate(),
      totalQuestions: data['totalQuestions'] ?? 0,
      participantCount: data['participantCount'] ?? 0,
    );
  }

  factory LiveQuizModel.fromFirestore(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>;
    return LiveQuizModel.fromJson({...data, 'id': snap.id});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'creatorId': creatorId,
      'title': title,
      'description': description,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'timePerQuestion': timePerQuestion,
      'autoAdvance': autoAdvance,
      'showLeaderboard': showLeaderboard,
      'allowAnonymous': allowAnonymous,
      'maxParticipants': maxParticipants,
      'currentQuestionIndex': currentQuestionIndex,
      'currentQuestionStartedAt': currentQuestionStartedAt != null 
          ? Timestamp.fromDate(currentQuestionStartedAt!) 
          : null,
      'totalQuestions': totalQuestions,
      'participantCount': participantCount,
    };
  }

  LiveQuizModel copyWith({
    String? id,
    String? eventId,
    String? creatorId,
    String? title,
    String? description,
    QuizStatus? status,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? endedAt,
    int? timePerQuestion,
    bool? autoAdvance,
    bool? showLeaderboard,
    bool? allowAnonymous,
    int? maxParticipants,
    int? currentQuestionIndex,
    DateTime? currentQuestionStartedAt,
    int? totalQuestions,
    int? participantCount,
  }) {
    return LiveQuizModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      creatorId: creatorId ?? this.creatorId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      timePerQuestion: timePerQuestion ?? this.timePerQuestion,
      autoAdvance: autoAdvance ?? this.autoAdvance,
      showLeaderboard: showLeaderboard ?? this.showLeaderboard,
      allowAnonymous: allowAnonymous ?? this.allowAnonymous,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      currentQuestionStartedAt: currentQuestionStartedAt ?? this.currentQuestionStartedAt,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      participantCount: participantCount ?? this.participantCount,
    );
  }

  // Helper methods
  bool get isLive => status == QuizStatus.live;
  bool get isDraft => status == QuizStatus.draft;
  bool get isEnded => status == QuizStatus.ended;
  bool get isPaused => status == QuizStatus.paused;
  bool get hasStarted => startedAt != null;
  
  bool get hasCurrentQuestion => currentQuestionIndex != null && 
      currentQuestionIndex! >= 0 && 
      currentQuestionIndex! < totalQuestions;
  
  Duration? get timeRemainingForCurrentQuestion {
    if (!hasCurrentQuestion || currentQuestionStartedAt == null) return null;
    
    final elapsed = DateTime.now().difference(currentQuestionStartedAt!);
    final remaining = Duration(seconds: timePerQuestion) - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
  
  bool get isCurrentQuestionExpired {
    final remaining = timeRemainingForCurrentQuestion;
    return remaining != null && remaining == Duration.zero;
  }
  
  double get progressPercentage {
    if (totalQuestions == 0) return 0.0;
    if (currentQuestionIndex == null) return 0.0;
    return (currentQuestionIndex! + 1) / totalQuestions;
  }
}
