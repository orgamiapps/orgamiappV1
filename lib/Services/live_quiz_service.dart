import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/models/live_quiz_model.dart';
import 'package:attendus/models/quiz_question_model.dart';
import 'package:attendus/models/quiz_participant_model.dart';
import 'package:attendus/models/quiz_response_model.dart';
import 'package:attendus/Utils/logger.dart';

typedef QuizCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> data,
    );

/// All quiz authority stays on the server. Read endpoints redact answers and
/// advance overdue questions against the server clock; clients only render them.
class LiveQuizService extends ChangeNotifier {
  static final LiveQuizService _instance = LiveQuizService._internal();
  factory LiveQuizService() => _instance;
  LiveQuizService._internal()
    : _caller = null,
      _uid = null,
      _ensureGuest = null;
  @visibleForTesting
  LiveQuizService.forTesting({
    required QuizCallable caller,
    required String? Function() currentUid,
    Future<void> Function()? ensureGuest,
  }) : _caller = caller,
       _uid = currentUid,
       _ensureGuest = ensureGuest;

  final QuizCallable? _caller;
  final String? Function()? _uid;
  final Future<void> Function()? _ensureGuest;
  final Map<String, int> _revisions = {};
  final Map<String, int> _questionSessions = {};
  final Set<StreamController<dynamic>> _controllers = {};
  final Map<String, int> _questionDeadlines = {};
  int _serverOffset = 0;
  String? _owner;
  bool _disposed = false;
  String? get _currentUid =>
      _uid != null ? _uid() : FirebaseAuth.instance.currentUser?.uid;

  void _bindOwner() {
    final uid = _currentUid;
    if (_owner != uid) {
      _owner = uid;
      _revisions.clear();
      _questionSessions.clear();
      _questionDeadlines.clear();
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (_currentUid == null) {
      if (_ensureGuest != null) {
        await _ensureGuest();
      } else if (_caller == null) {
        await GuestModeService().ensureGuestSession();
      }
    }
    _bindOwner();
    final uid = _currentUid;
    if (uid == null || _disposed) throw StateError('Sign in to continue.');
    final result = _caller != null
        ? await _caller(name, data)
        : Map<String, dynamic>.from(
            (await FirebaseFunctions.instance
                        .httpsCallable(name)
                        .call(data)
                        .timeout(const Duration(seconds: 25)))
                    .data
                as Map,
          );
    if (_disposed || _currentUid != uid) {
      throw StateError('Account changed. Open the quiz again.');
    }
    return result;
  }

  Future<dynamic> _read(
    String action, {
    String? quizId,
    String? eventId,
    String? questionId,
    String? participantId,
  }) async {
    final result = await _call('quizReadV1', {
      'action': action,
      'quizId': ?quizId,
      'eventId': ?eventId,
      'questionId': ?questionId,
      'participantId': ?participantId,
    });
    final data = result['data'];
    if (result['serverTime'] is num) {
      _serverOffset =
          (result['serverTime'] as num).toInt() -
          DateTime.now().millisecondsSinceEpoch;
    }
    if ((action == 'quiz' || action == 'getByEvent') && data is Map) {
      final id = data['id']?.toString();
      if (id != null && data['currentQuestionEndsAt'] is num) {
        _questionDeadlines[id] = (data['currentQuestionEndsAt'] as num).toInt();
      }
      if (id != null && data['revision'] is num) {
        _revisions[id] = (data['revision'] as num).toInt();
      }
    }
    return data;
  }

  Future<Map<String, dynamic>> _mutate(
    String action, {
    String? quizId,
    String? eventId,
    String? questionId,
    String? participantId,
    Map<String, dynamic> payload = const {},
  }) async {
    _bindOwner();
    const lifecycle = {'start', 'pause', 'resume', 'next', 'end', 'restart'};
    if (quizId != null &&
        lifecycle.contains(action) &&
        !_revisions.containsKey(quizId)) {
      await _read('quiz', quizId: quizId);
    }
    final data = <String, dynamic>{
      'action': action,
      'requestId': const Uuid().v4(),
      'quizId': ?quizId,
      'eventId': ?eventId,
      'questionId': ?questionId,
      'participantId': ?participantId,
      if (quizId != null && lifecycle.contains(action))
        'expectedRevision': _revisions[quizId],
      'payload': payload,
    };
    Map<String, dynamic> result;
    try {
      result = await _call('quizMutationV1', data);
    } on FirebaseFunctionsException catch (error) {
      if (!const {'unavailable', 'deadline-exceeded'}.contains(error.code)) {
        rethrow;
      }
      // Reuse the request identifier after an uncertain response.
      result = await _call('quizMutationV1', data);
    }
    final id = result['quizId']?.toString() ?? quizId;
    if (id != null && result['revision'] is num) {
      _revisions[id] = (result['revision'] as num).toInt();
    }
    return result;
  }

  Map<String, dynamic> _model(dynamic value) {
    final data = Map<String, dynamic>.from(value as Map);
    for (final field in [
      'createdAt',
      'startedAt',
      'endedAt',
      'currentQuestionStartedAt',
      'currentQuestionEndsAt',
      'joinedAt',
      'lastActiveAt',
      'submittedAt',
    ]) {
      if (data[field] is num) {
        data[field] = Timestamp.fromMillisecondsSinceEpoch(
          (data[field] as num).toInt(),
        );
      }
    }
    return data;
  }

  QuizQuestionModel _question(dynamic value) {
    final data = _model(value);
    if (data['session'] is num) {
      _questionSessions[data['id'].toString()] = (data['session'] as num)
          .toInt();
    }
    return QuizQuestionModel.fromJson(data);
  }

  Future<bool> _success(Future<Map<String, dynamic>> Function() work) async {
    try {
      return (await work())['ok'] == true;
    } catch (error) {
      Logger.error('Quiz request failed: $error');
      return false;
    }
  }

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
      final result = await _mutate(
        'create',
        eventId: eventId,
        payload: {
          'title': title,
          'description': description,
          'timePerQuestion': timePerQuestion,
          'autoAdvance': autoAdvance,
          'showLeaderboard': showLeaderboard,
          'allowAnonymous': allowAnonymous,
          'maxParticipants': maxParticipants,
        },
      );
      return result['quizId'] as String?;
    } catch (error) {
      Logger.error('Quiz creation failed: $error');
      return null;
    }
  }

  Future<bool> updateQuiz(String quizId, Map<String, dynamic> updates) =>
      _success(() => _mutate('update', quizId: quizId, payload: updates));
  Future<bool> deleteQuiz(String quizId) =>
      _success(() => _mutate('delete', quizId: quizId));
  Future<String?> addQuestion(QuizQuestionModel question) async {
    try {
      return (await _mutate(
            'addQuestion',
            quizId: question.quizId,
            payload: question.toJson(),
          ))['questionId']
          as String?;
    } catch (error) {
      Logger.error('Question creation failed: $error');
      return null;
    }
  }

  Future<bool> updateQuestion(
    String questionId,
    Map<String, dynamic> updates,
  ) => _success(
    () => _mutate('updateQuestion', questionId: questionId, payload: updates),
  );
  Future<bool> deleteQuestion(String questionId, String quizId) => _success(
    () => _mutate('deleteQuestion', quizId: quizId, questionId: questionId),
  );
  Future<bool> reorderQuestions(String quizId, List<String> questionIds) =>
      _success(
        () => _mutate(
          'reorderQuestions',
          quizId: quizId,
          payload: {'questionIds': questionIds},
        ),
      );
  Future<bool> startQuiz(String quizId) =>
      _success(() => _mutate('start', quizId: quizId));
  Future<bool> pauseQuiz(String quizId) =>
      _success(() => _mutate('pause', quizId: quizId));
  Future<bool> resumeQuiz(String quizId) =>
      _success(() => _mutate('resume', quizId: quizId));
  Future<bool> nextQuestion(String quizId) =>
      _success(() => _mutate('next', quizId: quizId));
  Future<bool> endQuiz(String quizId) =>
      _success(() => _mutate('end', quizId: quizId));
  Future<bool> restartQuiz(String quizId, {bool keepParticipants = false}) =>
      _success(
        () => _mutate(
          'restart',
          quizId: quizId,
          payload: {'keepParticipants': keepParticipants},
        ),
      );
  Future<String?> joinQuiz({
    required String quizId,
    String? displayName,
    bool isAnonymous = true,
  }) async {
    try {
      return (await _mutate(
            'join',
            quizId: quizId,
            payload: {'displayName': displayName, 'isAnonymous': isAnonymous},
          ))['participantId']
          as String?;
    } catch (error) {
      Logger.error('Quiz join failed: $error');
      return null;
    }
  }

  Future<bool> leaveQuiz(String quizId, String participantId) => _success(
    () => _mutate('leave', quizId: quizId, participantId: participantId),
  );
  Future<bool> submitAnswer({
    required String quizId,
    required String questionId,
    required String participantId,
    required int questionIndex,
    required dynamic answer,
    required int timeToAnswer,
    int? session,
  }) async {
    _bindOwner();
    final displayedSession = session ?? _questionSessions[questionId];
    if (displayedSession == null) return false;
    return _success(
      () => _mutate(
        'submitAnswer',
        quizId: quizId,
        questionId: questionId,
        participantId: participantId,
        payload: {'answer': answer, 'session': displayedSession},
      ),
    );
  }

  Stream<T> _poll<T>(Future<T?> Function() load) {
    late StreamController<T> controller;
    Timer? timer;
    bool busy = false;
    String? owner = _currentUid;
    Future<void> tick() async {
      if (busy || _disposed || controller.isClosed) return;
      if (owner != null && _currentUid != owner) {
        timer?.cancel();
        controller.addError(
          StateError('Account changed. Open the quiz again.'),
        );
        await controller.close();
        return;
      }
      busy = true;
      try {
        final data = await load();
        owner ??= _currentUid;
        if (!controller.isClosed && data != null) controller.add(data);
      } catch (error, stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      } finally {
        busy = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        tick();
        timer = Timer.periodic(const Duration(seconds: 2), (_) => tick());
      },
      onCancel: () {
        timer?.cancel();
        _controllers.remove(controller);
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  Stream<LiveQuizModel> getQuizStream(String quizId) => _poll(() async {
    final data = await _read('quiz', quizId: quizId);
    return data == null ? null : LiveQuizModel.fromJson(_model(data));
  });
  Stream<List<QuizParticipantModel>> getParticipantsStream(String quizId) =>
      _poll(
        () async => ((await _read('participants', quizId: quizId)) as List)
            .map((item) => QuizParticipantModel.fromJson(_model(item)))
            .toList(),
      );
  Stream<List<QuizQuestionModel>> getQuestionsStream(String quizId) => _poll(
    () async => ((await _read('questions', quizId: quizId)) as List)
        .map(_question)
        .toList(),
  );
  Future<LiveQuizModel?> getQuiz(String quizId) async {
    final data = await _read('quiz', quizId: quizId);
    return data == null ? null : LiveQuizModel.fromJson(_model(data));
  }

  Future<LiveQuizModel?> getQuizByEventId(String eventId) async {
    final data = await _read('getByEvent', eventId: eventId);
    return data == null ? null : LiveQuizModel.fromJson(_model(data));
  }

  Future<List<QuizQuestionModel>> getQuestions(String quizId) async =>
      ((await _read('questions', quizId: quizId)) as List)
          .map(_question)
          .toList();
  Future<QuizQuestionModel?> getCurrentQuestion(String quizId) async {
    final data = await _read('currentQuestion', quizId: quizId);
    return data == null ? null : _question(data);
  }

  Duration remainingTime(String quizId) {
    final remaining =
        (_questionDeadlines[quizId] ?? 0) -
        DateTime.now().millisecondsSinceEpoch -
        _serverOffset;
    return Duration(milliseconds: remaining < 0 ? 0 : remaining);
  }

  Future<QuizParticipantModel?> getOwnParticipant(String quizId) async {
    final data = await _read('participant', quizId: quizId);
    return data == null ? null : QuizParticipantModel.fromJson(_model(data));
  }

  Stream<QuizParticipantModel> getParticipantStream(String participantId) =>
      _poll(() => getParticipant(participantId));
  Future<QuizParticipantModel?> getParticipant(String participantId) async {
    final data = await _read('participant', participantId: participantId);
    return data == null ? null : QuizParticipantModel.fromJson(_model(data));
  }

  Future<List<QuizResponseModel>> getQuestionResponses(
    String questionId,
  ) async =>
      ((await _read('questionResponses', questionId: questionId)) as List)
          .map((item) => QuizResponseModel.fromJson(_model(item)))
          .toList();
  Future<QuizResponseModel?> getParticipantResponse(
    String participantId,
    String questionId,
  ) async {
    final data = await _read(
      'participantResponse',
      participantId: participantId,
      questionId: questionId,
    );
    return data == null ? null : QuizResponseModel.fromJson(_model(data));
  }

  Future<bool> hasParticipantAnswered(
    String participantId,
    String questionId,
  ) async => await getParticipantResponse(participantId, questionId) != null;
  Future<Map<String, dynamic>> getQuizStats(String quizId) async =>
      Map<String, dynamic>.from(await _read('stats', quizId: quizId) as Map);

  @override
  void dispose() {
    _disposed = true;
    for (final controller in _controllers.toList()) {
      controller.close();
    }
    _controllers.clear();
    super.dispose();
  }
}
