import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/models/live_quiz_model.dart';
import 'package:attendus/models/quiz_question_model.dart';
import 'package:attendus/models/quiz_participant_model.dart';
import 'package:attendus/models/quiz_response_model.dart';
import 'package:attendus/Utils/logger.dart';

class LiveQuizService extends ChangeNotifier {
  static final LiveQuizService _instance = LiveQuizService._internal();
  factory LiveQuizService() => _instance;
  LiveQuizService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream controllers for real-time updates
  final Map<String, StreamController<LiveQuizModel>> _quizStreamControllers = {};
  final Map<String, StreamController<List<QuizParticipantModel>>> _participantStreamControllers = {};
  final Map<String, StreamController<QuestionResponseStats>> _responseStreamControllers = {};
  final Map<String, StreamController<List<QuizQuestionModel>>> _questionStreamControllers = {};

  // Active subscriptions
  final Map<String, StreamSubscription> _activeSubscriptions = {};

  // Timers for automatic question progression
  final Map<String, Timer> _questionTimers = {};

  @override
  void dispose() {
    _disposeAllStreams();
    _cancelAllTimers();
    super.dispose();
  }

  void _disposeAllStreams() {
    for (final controller in _quizStreamControllers.values) {
      controller.close();
    }
    for (final controller in _participantStreamControllers.values) {
      controller.close();
    }
    for (final controller in _responseStreamControllers.values) {
      controller.close();
    }
    for (final controller in _questionStreamControllers.values) {
      controller.close();
    }
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    
    _quizStreamControllers.clear();
    _participantStreamControllers.clear();
    _responseStreamControllers.clear();
    _questionStreamControllers.clear();
    _activeSubscriptions.clear();
  }

  void _cancelAllTimers() {
    for (final timer in _questionTimers.values) {
      timer.cancel();
    }
    _questionTimers.clear();
  }

  // ============================================================================
  // QUIZ MANAGEMENT
  // ============================================================================

  /// Create a new live quiz for an event
  Future<String?> createLiveQuiz({
    required String eventId,
    required String title,
    String? description,
    int timePerQuestion = 30,
    bool autoAdvance = true,
    bool showLeaderboard = true,
    bool allowAnonymous = true,
    int maxParticipants = 1000,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final quizRef = _firestore.collection(LiveQuizModel.firebaseKey).doc();
      final quiz = LiveQuizModel(
        id: quizRef.id,
        eventId: eventId,
        creatorId: user.uid,
        title: title,
        description: description,
        status: QuizStatus.draft,
        createdAt: DateTime.now(),
        timePerQuestion: timePerQuestion,
        autoAdvance: autoAdvance,
        showLeaderboard: showLeaderboard,
        allowAnonymous: allowAnonymous,
        maxParticipants: maxParticipants,
      );

      await quizRef.set(quiz.toJson());
      
      // Update the associated event
      await _firestore.collection('Events').doc(eventId).update({
        'hasLiveQuiz': true,
        'liveQuizId': quizRef.id,
      });

      Logger.info('Live quiz created: ${quizRef.id}');
      return quizRef.id;
    } catch (e) {
      Logger.error('Failed to create live quiz: $e');
      return null;
    }
  }

  /// Update quiz settings
  Future<bool> updateQuiz(String quizId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update(updates);
      return true;
    } catch (e) {
      Logger.error('Failed to update quiz: $e');
      return false;
    }
  }

  /// Delete a quiz and all associated data
  Future<bool> deleteQuiz(String quizId) async {
    try {
      final batch = _firestore.batch();
      
      // Delete quiz document
      batch.delete(_firestore.collection(LiveQuizModel.firebaseKey).doc(quizId));
      
      // Delete all questions
      final questionsSnapshot = await _firestore
          .collection(QuizQuestionModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .get();
      
      for (final doc in questionsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // Delete all participants
      final participantsSnapshot = await _firestore
          .collection(QuizParticipantModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .get();
      
      for (final doc in participantsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // Delete all responses
      final responsesSnapshot = await _firestore
          .collection(QuizResponseModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .get();
      
      for (final doc in responsesSnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      
      // Clean up local streams
      _cleanupQuizStreams(quizId);
      
      Logger.info('Quiz deleted: $quizId');
      return true;
    } catch (e) {
      Logger.error('Failed to delete quiz: $e');
      return false;
    }
  }

  void _cleanupQuizStreams(String quizId) {
    _quizStreamControllers[quizId]?.close();
    _participantStreamControllers[quizId]?.close();
    _responseStreamControllers[quizId]?.close();
    _questionStreamControllers[quizId]?.close();
    
    _quizStreamControllers.remove(quizId);
    _participantStreamControllers.remove(quizId);
    _responseStreamControllers.remove(quizId);
    _questionStreamControllers.remove(quizId);
    
    _activeSubscriptions[quizId]?.cancel();
    _activeSubscriptions.remove(quizId);
    
    _questionTimers[quizId]?.cancel();
    _questionTimers.remove(quizId);
  }

  // ============================================================================
  // QUESTION MANAGEMENT
  // ============================================================================

  /// Add a question to a quiz
  Future<String?> addQuestion(QuizQuestionModel question) async {
    try {
      final questionRef = _firestore.collection(QuizQuestionModel.firebaseKey).doc();
      final questionWithId = question.copyWith(id: questionRef.id);
      
      await questionRef.set(questionWithId.toJson());
      
      // Update quiz total questions count
      await _updateQuizQuestionCount(question.quizId);
      
      return questionRef.id;
    } catch (e) {
      Logger.error('Failed to add question: $e');
      return null;
    }
  }

  /// Update a question
  Future<bool> updateQuestion(String questionId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection(QuizQuestionModel.firebaseKey).doc(questionId).update(updates);
      return true;
    } catch (e) {
      Logger.error('Failed to update question: $e');
      return false;
    }
  }

  /// Delete a question
  Future<bool> deleteQuestion(String questionId, String quizId) async {
    try {
      await _firestore.collection(QuizQuestionModel.firebaseKey).doc(questionId).delete();
      await _updateQuizQuestionCount(quizId);
      return true;
    } catch (e) {
      Logger.error('Failed to delete question: $e');
      return false;
    }
  }

  /// Reorder questions
  Future<bool> reorderQuestions(String quizId, List<String> questionIds) async {
    try {
      final batch = _firestore.batch();
      
      for (int i = 0; i < questionIds.length; i++) {
        final questionRef = _firestore.collection(QuizQuestionModel.firebaseKey).doc(questionIds[i]);
        batch.update(questionRef, {'orderIndex': i});
      }
      
      await batch.commit();
      return true;
    } catch (e) {
      Logger.error('Failed to reorder questions: $e');
      return false;
    }
  }

  Future<void> _updateQuizQuestionCount(String quizId) async {
    final questionsSnapshot = await _firestore
        .collection(QuizQuestionModel.firebaseKey)
        .where('quizId', isEqualTo: quizId)
        .get();
    
    await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
      'totalQuestions': questionsSnapshot.docs.length,
    });
  }

  // ============================================================================
  // QUIZ SESSION MANAGEMENT
  // ============================================================================

  /// Start a live quiz session
  Future<bool> startQuiz(String quizId) async {
    try {
      final now = DateTime.now();
      
      await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
        'status': QuizStatus.live.name,
        'startedAt': Timestamp.fromDate(now),
        'currentQuestionIndex': 0,
        'currentQuestionStartedAt': Timestamp.fromDate(now),
      });
      
      // Start automatic progression timer if enabled
      final quiz = await getQuiz(quizId);
      if (quiz != null && quiz.autoAdvance) {
        _startQuestionTimer(quizId, quiz.timePerQuestion);
      }
      
      Logger.info('Quiz started: $quizId');
      return true;
    } catch (e) {
      Logger.error('Failed to start quiz: $e');
      return false;
    }
  }

  /// Pause a live quiz
  Future<bool> pauseQuiz(String quizId) async {
    try {
      await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
        'status': QuizStatus.paused.name,
      });
      
      // Cancel automatic progression
      _questionTimers[quizId]?.cancel();
      _questionTimers.remove(quizId);
      
      return true;
    } catch (e) {
      Logger.error('Failed to pause quiz: $e');
      return false;
    }
  }

  /// Resume a paused quiz
  Future<bool> resumeQuiz(String quizId) async {
    try {
      final now = DateTime.now();
      
      await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
        'status': QuizStatus.live.name,
        'currentQuestionStartedAt': Timestamp.fromDate(now),
      });
      
      // Restart timer with remaining time
      final quiz = await getQuiz(quizId);
      if (quiz != null && quiz.autoAdvance) {
        _startQuestionTimer(quizId, quiz.timePerQuestion);
      }
      
      return true;
    } catch (e) {
      Logger.error('Failed to resume quiz: $e');
      return false;
    }
  }

  /// Move to next question
  Future<bool> nextQuestion(String quizId) async {
    try {
      final quiz = await getQuiz(quizId);
      if (quiz == null) return false;
      
      final nextIndex = (quiz.currentQuestionIndex ?? -1) + 1;
      
      if (nextIndex >= quiz.totalQuestions) {
        // Automatically end quiz when all questions are completed
        Logger.info('All questions completed, ending quiz: $quizId');
        return await endQuiz(quizId);
      }
      
      final now = DateTime.now();
      await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
        'currentQuestionIndex': nextIndex,
        'currentQuestionStartedAt': Timestamp.fromDate(now),
      });
      
      // Update leaderboard after each question
      await _updateLeaderboard(quizId);
      
      // Start timer for new question if auto-advance is enabled
      // Quiz continues regardless of event timing
      if (quiz.autoAdvance) {
        _startQuestionTimer(quizId, quiz.timePerQuestion);
      }
      
      Logger.info('Advanced to question ${nextIndex + 1}/${quiz.totalQuestions} in quiz: $quizId');
      return true;
    } catch (e) {
      Logger.error('Failed to move to next question: $e');
      return false;
    }
  }

  /// End the quiz (manually by host or automatically when all questions completed)
  Future<bool> endQuiz(String quizId) async {
    try {
      final now = DateTime.now();
      
      await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
        'status': QuizStatus.ended.name,
        'endedAt': Timestamp.fromDate(now),
      });
      
      // Final leaderboard update
      await _updateLeaderboard(quizId);
      
      // Cancel any running timers
      _questionTimers[quizId]?.cancel();
      _questionTimers.remove(quizId);
      
      Logger.info('Quiz ended: $quizId - Quiz remains accessible for viewing results');
      return true;
    } catch (e) {
      Logger.error('Failed to end quiz: $e');
      return false;
    }
  }

  void _startQuestionTimer(String quizId, int timeLimit) {
    // Cancel existing timer
    _questionTimers[quizId]?.cancel();
    
    // Start new timer - quiz continues automatically until all questions are answered
    _questionTimers[quizId] = Timer(Duration(seconds: timeLimit), () async {
      // Continue to next question regardless of event timing
      await nextQuestion(quizId);
    });
  }

  // ============================================================================
  // PARTICIPANT MANAGEMENT
  // ============================================================================

  /// Join a quiz as a participant
  Future<String?> joinQuiz({
    required String quizId,
    String? displayName,
    bool isAnonymous = true,
  }) async {
    try {
      final user = _auth.currentUser;
      
      // Create participant
      final participantRef = _firestore.collection(QuizParticipantModel.firebaseKey).doc();
      
      QuizParticipantModel participant;
      if (isAnonymous || user == null) {
        participant = QuizParticipantModel.anonymous(
          quizId: quizId,
          customDisplayName: displayName,
        );
      } else {
        participant = QuizParticipantModel.authenticated(
          quizId: quizId,
          userId: user.uid,
          displayName: displayName ?? user.displayName ?? user.email ?? 'User',
        );
      }
      
      final participantWithId = participant.copyWith(id: participantRef.id);
      await participantRef.set(participantWithId.toJson());
      
      // Update participant count
      await _incrementParticipantCount(quizId);
      
      Logger.info('Participant joined quiz: $quizId');
      return participantRef.id;
    } catch (e) {
      Logger.error('Failed to join quiz: $e');
      return null;
    }
  }

  /// Leave a quiz
  Future<bool> leaveQuiz(String quizId, String participantId) async {
    try {
      // Mark participant as inactive
      await _firestore.collection(QuizParticipantModel.firebaseKey).doc(participantId).update({
        'isActive': false,
      });
      
      await _decrementParticipantCount(quizId);
      
      return true;
    } catch (e) {
      Logger.error('Failed to leave quiz: $e');
      return false;
    }
  }

  Future<void> _incrementParticipantCount(String quizId) async {
    await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
      'participantCount': FieldValue.increment(1),
    });
  }

  Future<void> _decrementParticipantCount(String quizId) async {
    await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).update({
      'participantCount': FieldValue.increment(-1),
    });
  }

  // ============================================================================
  // ANSWER SUBMISSION
  // ============================================================================

  /// Submit an answer for a question
  Future<bool> submitAnswer({
    required String quizId,
    required String questionId,
    required String participantId,
    required int questionIndex,
    required dynamic answer,
    required int timeToAnswer,
  }) async {
    try {
      // Get question to check correctness
      final questionDoc = await _firestore
          .collection(QuizQuestionModel.firebaseKey)
          .doc(questionId)
          .get();
      
      if (!questionDoc.exists) return false;
      
      final question = QuizQuestionModel.fromFirestore(questionDoc);
      final isCorrect = question.isAnswerCorrect(answer);
      final similarityScore = question.type == QuestionType.shortAnswer 
          ? question.getAnswerSimilarity(answer.toString())
          : null;
      
      // Create response
      final response = QuizResponseModel.create(
        quizId: quizId,
        questionId: questionId,
        participantId: participantId,
        questionIndex: questionIndex,
        answer: answer,
        isCorrect: isCorrect,
        basePoints: question.points,
        timeToAnswer: timeToAnswer,
        questionTimeLimit: question.timeLimit,
        similarityScore: similarityScore,
      );
      
      // Save response
      final responseRef = _firestore.collection(QuizResponseModel.firebaseKey).doc();
      await responseRef.set(response.copyWith(id: responseRef.id).toJson());
      
      // Update participant stats
      await _updateParticipantStats(participantId, isCorrect, response.totalPoints);
      
      return true;
    } catch (e) {
      Logger.error('Failed to submit answer: $e');
      return false;
    }
  }

  Future<void> _updateParticipantStats(String participantId, bool isCorrect, int pointsEarned) async {
    final updates = <String, dynamic>{
      'questionsAnswered': FieldValue.increment(1),
      'currentScore': FieldValue.increment(pointsEarned),
      'lastActiveAt': Timestamp.fromDate(DateTime.now()),
    };
    
    if (isCorrect) {
      updates['correctAnswers'] = FieldValue.increment(1);
    }
    
    await _firestore.collection(QuizParticipantModel.firebaseKey).doc(participantId).update(updates);
  }

  Future<void> _updateLeaderboard(String quizId) async {
    try {
      // Get all active participants sorted by score
      final participantsSnapshot = await _firestore
          .collection(QuizParticipantModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .where('isActive', isEqualTo: true)
          .orderBy('currentScore', descending: true)
          .get();
      
      // Update ranks
      final batch = _firestore.batch();
      for (int i = 0; i < participantsSnapshot.docs.length; i++) {
        final participantRef = participantsSnapshot.docs[i].reference;
        final currentRank = i + 1;
        
        // Get current best rank
        final currentData = participantsSnapshot.docs[i].data();
        final currentBestRank = currentData['bestRank'] as int?;
        final newBestRank = currentBestRank == null || currentRank < currentBestRank 
            ? currentRank 
            : currentBestRank;
        
        batch.update(participantRef, {
          'currentRank': currentRank,
          'bestRank': newBestRank,
        });
      }
      
      await batch.commit();
    } catch (e) {
      Logger.error('Failed to update leaderboard: $e');
    }
  }

  // ============================================================================
  // REAL-TIME STREAMS
  // ============================================================================

  /// Get real-time quiz updates
  Stream<LiveQuizModel> getQuizStream(String quizId) {
    if (!_quizStreamControllers.containsKey(quizId)) {
      _quizStreamControllers[quizId] = StreamController<LiveQuizModel>.broadcast();
      
      final subscription = _firestore
          .collection(LiveQuizModel.firebaseKey)
          .doc(quizId)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists) {
            final quiz = LiveQuizModel.fromFirestore(snapshot);
            _quizStreamControllers[quizId]?.add(quiz);
          }
        },
        onError: (error) {
          Logger.error('Quiz stream error: $error');
          _quizStreamControllers[quizId]?.addError(error);
        },
      );
      
      _activeSubscriptions['quiz_$quizId'] = subscription;
    }
    
    return _quizStreamControllers[quizId]!.stream;
  }

  /// Get real-time participants list
  Stream<List<QuizParticipantModel>> getParticipantsStream(String quizId) {
    if (!_participantStreamControllers.containsKey(quizId)) {
      _participantStreamControllers[quizId] = StreamController<List<QuizParticipantModel>>.broadcast();
      
      final subscription = _firestore
          .collection(QuizParticipantModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .where('isActive', isEqualTo: true)
          .orderBy('currentScore', descending: true)
          .snapshots()
          .listen(
        (snapshot) {
          final participants = snapshot.docs
              .map((doc) => QuizParticipantModel.fromFirestore(doc))
              .toList();
          _participantStreamControllers[quizId]?.add(participants);
        },
        onError: (error) {
          Logger.error('Participants stream error: $error');
          _participantStreamControllers[quizId]?.addError(error);
        },
      );
      
      _activeSubscriptions['participants_$quizId'] = subscription;
    }
    
    return _participantStreamControllers[quizId]!.stream;
  }

  /// Get quiz questions stream
  Stream<List<QuizQuestionModel>> getQuestionsStream(String quizId) {
    if (!_questionStreamControllers.containsKey(quizId)) {
      _questionStreamControllers[quizId] = StreamController<List<QuizQuestionModel>>.broadcast();
      
      final subscription = _firestore
          .collection(QuizQuestionModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .orderBy('orderIndex')
          .snapshots()
          .listen(
        (snapshot) {
          final questions = snapshot.docs
              .map((doc) => QuizQuestionModel.fromFirestore(doc))
              .toList();
          _questionStreamControllers[quizId]?.add(questions);
        },
        onError: (error) {
          Logger.error('Questions stream error: $error');
          _questionStreamControllers[quizId]?.addError(error);
        },
      );
      
      _activeSubscriptions['questions_$quizId'] = subscription;
    }
    
    return _questionStreamControllers[quizId]!.stream;
  }

  // ============================================================================
  // DATA QUERIES
  // ============================================================================

  /// Get a single quiz
  Future<LiveQuizModel?> getQuiz(String quizId) async {
    try {
      final doc = await _firestore.collection(LiveQuizModel.firebaseKey).doc(quizId).get();
      return doc.exists ? LiveQuizModel.fromFirestore(doc) : null;
    } catch (e) {
      Logger.error('Failed to get quiz: $e');
      return null;
    }
  }

  /// Get quiz by event ID
  Future<LiveQuizModel?> getQuizByEventId(String eventId) async {
    try {
      final snapshot = await _firestore
          .collection(LiveQuizModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .limit(1)
          .get();
      
      return snapshot.docs.isNotEmpty 
          ? LiveQuizModel.fromFirestore(snapshot.docs.first)
          : null;
    } catch (e) {
      Logger.error('Failed to get quiz by event ID: $e');
      return null;
    }
  }

  /// Get questions for a quiz
  Future<List<QuizQuestionModel>> getQuestions(String quizId) async {
    try {
      final snapshot = await _firestore
          .collection(QuizQuestionModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .orderBy('orderIndex')
          .get();
      
      return snapshot.docs.map((doc) => QuizQuestionModel.fromFirestore(doc)).toList();
    } catch (e) {
      Logger.error('Failed to get questions: $e');
      return [];
    }
  }

  /// Get current question for a quiz
  Future<QuizQuestionModel?> getCurrentQuestion(String quizId) async {
    try {
      final quiz = await getQuiz(quizId);
      if (quiz == null || !quiz.hasCurrentQuestion) return null;
      
      final snapshot = await _firestore
          .collection(QuizQuestionModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .where('orderIndex', isEqualTo: quiz.currentQuestionIndex)
          .limit(1)
          .get();
      
      return snapshot.docs.isNotEmpty 
          ? QuizQuestionModel.fromFirestore(snapshot.docs.first)
          : null;
    } catch (e) {
      Logger.error('Failed to get current question: $e');
      return null;
    }
  }

  /// Get participant by ID
  Future<QuizParticipantModel?> getParticipant(String participantId) async {
    try {
      final doc = await _firestore.collection(QuizParticipantModel.firebaseKey).doc(participantId).get();
      return doc.exists ? QuizParticipantModel.fromFirestore(doc) : null;
    } catch (e) {
      Logger.error('Failed to get participant: $e');
      return null;
    }
  }

  /// Get responses for a question
  Future<List<QuizResponseModel>> getQuestionResponses(String questionId) async {
    try {
      final snapshot = await _firestore
          .collection(QuizResponseModel.firebaseKey)
          .where('questionId', isEqualTo: questionId)
          .get();
      
      return snapshot.docs.map((doc) => QuizResponseModel.fromFirestore(doc)).toList();
    } catch (e) {
      Logger.error('Failed to get question responses: $e');
      return [];
    }
  }

  /// Get participant's response for a specific question
  Future<QuizResponseModel?> getParticipantResponse(String participantId, String questionId) async {
    try {
      final snapshot = await _firestore
          .collection(QuizResponseModel.firebaseKey)
          .where('participantId', isEqualTo: participantId)
          .where('questionId', isEqualTo: questionId)
          .limit(1)
          .get();
      
      return snapshot.docs.isNotEmpty 
          ? QuizResponseModel.fromFirestore(snapshot.docs.first)
          : null;
    } catch (e) {
      Logger.error('Failed to get participant response: $e');
      return null;
    }
  }

  /// Check if participant has already answered current question
  Future<bool> hasParticipantAnswered(String participantId, String questionId) async {
    final response = await getParticipantResponse(participantId, questionId);
    return response != null;
  }

  /// Get quiz statistics
  Future<Map<String, dynamic>> getQuizStats(String quizId) async {
    try {
      final quiz = await getQuiz(quizId);
      if (quiz == null) return {};
      
      final participantsSnapshot = await _firestore
          .collection(QuizParticipantModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .get();
      
      final responsesSnapshot = await _firestore
          .collection(QuizResponseModel.firebaseKey)
          .where('quizId', isEqualTo: quizId)
          .get();
      
      final totalParticipants = participantsSnapshot.docs.length;
      final activeParticipants = participantsSnapshot.docs
          .where((doc) => doc.data()['isActive'] == true)
          .length;
      final totalResponses = responsesSnapshot.docs.length;
      final correctResponses = responsesSnapshot.docs
          .where((doc) => doc.data()['isCorrect'] == true)
          .length;
      
      return {
        'totalParticipants': totalParticipants,
        'activeParticipants': activeParticipants,
        'totalResponses': totalResponses,
        'correctResponses': correctResponses,
        'averageAccuracy': totalResponses > 0 
            ? (correctResponses / totalResponses) * 100 
            : 0.0,
        'questionsAsked': quiz.currentQuestionIndex != null 
            ? quiz.currentQuestionIndex! + 1 
            : 0,
        'totalQuestions': quiz.totalQuestions,
        'progress': quiz.progressPercentage * 100,
      };
    } catch (e) {
      Logger.error('Failed to get quiz stats: $e');
      return {};
    }
  }
}
