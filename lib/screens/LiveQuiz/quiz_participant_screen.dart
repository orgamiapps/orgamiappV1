import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/models/live_quiz_model.dart';
import 'package:attendus/models/quiz_question_model.dart';
import 'package:attendus/models/quiz_participant_model.dart';
import 'package:attendus/Services/live_quiz_service.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/screens/LiveQuiz/widgets/live_leaderboard_widget.dart';

class QuizParticipantScreen extends StatefulWidget {
  final String quizId;
  final String? displayName;
  final bool isAnonymous;

  const QuizParticipantScreen({
    super.key,
    required this.quizId,
    this.displayName,
    this.isAnonymous = true,
  });

  @override
  State<QuizParticipantScreen> createState() => _QuizParticipantScreenState();
}

class _QuizParticipantScreenState extends State<QuizParticipantScreen>
    with TickerProviderStateMixin {
  final _liveQuizService = LiveQuizService();

  // Quiz State
  LiveQuizModel? _quiz;
  QuizQuestionModel? _currentQuestion;
  QuizParticipantModel? _participant;
  String? _participantId;

  // UI State
  bool _isJoining = true;
  bool _hasAnswered = false;
  bool _showingResults = false;
  bool _wasAnswerCorrect = false;
  dynamic _selectedAnswer;
  dynamic _correctAnswer;
  int _timeRemaining = 0;
  Timer? _countdownTimer;
  DateTime? _questionStartTime;
  int _pointsEarned = 0;
  String? _explanation;
  String? _errorMessage;
  bool _hasError = false;
  bool _isConnected = true; // Connection status indicator

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _celebrationController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _celebrationAnimation;

  // Streams
  StreamSubscription<LiveQuizModel>? _quizSubscription;
  StreamSubscription<List<QuizParticipantModel>>? _participantsSubscription;

  // Question Answer Controller
  final TextEditingController _textAnswerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _joinQuiz();
    _setupQuizStream();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _celebrationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.elasticOut),
    );

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _celebrationController.dispose();
    _countdownTimer?.cancel();
    _quizSubscription?.cancel();
    _participantsSubscription?.cancel();
    _textAnswerController.dispose();
    super.dispose();
  }

  Future<void> _joinQuiz() async {
    try {
      // Add timeout to joining process
      final participantId = await _liveQuizService.joinQuiz(
        quizId: widget.quizId,
        displayName: widget.displayName,
        isAnonymous: widget.isAnonymous,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your internet and try again.');
        },
      );

      if (participantId != null) {
        if (!mounted) return;
        setState(() {
          _participantId = participantId;
          _isJoining = false;
          _hasError = false;
        });

        // Get initial participant data asynchronously
        _loadParticipantDataAsync(participantId);
      } else {
        _handleJoinError('Failed to join quiz. Please try again.');
      }
    } catch (e) {
      Logger.error('Error joining quiz: $e');
      _handleJoinError('Error joining quiz: ${e.toString()}');
    }
  }

  Future<void> _loadParticipantDataAsync(String participantId) async {
    try {
      final participant = await _liveQuizService.getParticipant(participantId);
      if (mounted) {
        setState(() => _participant = participant);
      }
    } catch (e) {
      Logger.error('Error loading participant data: $e');
      // Non-critical error, don't block the quiz
    }
  }

  void _handleJoinError(String message) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _errorMessage = message;
      _isJoining = false;
    });
    _showError(message);
  }

  void _setupQuizStream() {
    _quizSubscription = _liveQuizService
        .getQuizStream(widget.quizId)
        .listen(
          (quiz) {
            // Update connection status
            if (mounted && !_isConnected) {
              setState(() => _isConnected = true);
            }
            
            final previousQuestion = _currentQuestion;
            final previousQuestionIndex = _quiz?.currentQuestionIndex;
            setState(() => _quiz = quiz);

            if (quiz.isLive && quiz.hasCurrentQuestion) {
              // Only reload question if it changed
              if (previousQuestionIndex != quiz.currentQuestionIndex) {
                _loadCurrentQuestion(quiz.currentQuestionIndex!);
                // Reset answer state for new questions
                _resetAnswerState();
              }

              _startCountdown();
            } else if (quiz.isEnded) {
              // Quiz ended - show final results
              _countdownTimer?.cancel();
            }
          },
          onError: (error) {
            Logger.error('Quiz stream error: $error');
            if (mounted) {
              setState(() => _isConnected = false);
            }
            _showError('Connection issue. Reconnecting...');
            // Try to reconnect after a delay
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                _setupQuizStream();
              }
            });
          },
        );
  }

  Future<void> _loadCurrentQuestion(int questionIndex) async {
    try {
      // Optimized: Only load the current question, not all questions
      final question = await _liveQuizService.getCurrentQuestion(widget.quizId).timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      
      if (question != null && mounted) {
        setState(() => _currentQuestion = question);

        // Check if participant has already answered this question
        if (_participantId != null) {
          final hasAnswered = await _liveQuizService.hasParticipantAnswered(
            _participantId!,
            question.id,
          );
          if (mounted) {
            setState(() => _hasAnswered = hasAnswered);
          }
        }
      }
    } catch (e) {
      Logger.error('Error loading question: $e');
      _showError('Error loading question. Retrying...');
      // Retry once after a short delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _loadCurrentQuestion(questionIndex);
      }
    }
  }

  void _resetAnswerState() {
    setState(() {
      _hasAnswered = false;
      _showingResults = false;
      _wasAnswerCorrect = false;
      _selectedAnswer = null;
      _correctAnswer = null;
      _pointsEarned = 0;
      _explanation = null;
      _textAnswerController.clear();
    });
  }

  void _startCountdown() {
    if (_quiz == null || !_quiz!.hasCurrentQuestion) return;

    _countdownTimer?.cancel();
    _questionStartTime = DateTime.now();

    final timeLimit = _currentQuestion?.timeLimit ?? _quiz!.timePerQuestion;
    setState(() => _timeRemaining = timeLimit);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0 && !_showingResults) {
        setState(() => _timeRemaining--);
      } else {
        timer.cancel();
        if (_hasAnswered && !_showingResults) {
          _showAnswerResults();
        } else if (!_hasAnswered) {
          _showTimeUpAndResults();
        }
      }
    });
  }

  void _showTimeUpAndResults() {
    // Store correct answer information for results display
    if (_currentQuestion != null) {
      _correctAnswer = _getCorrectAnswerForDisplay();
      _explanation = _currentQuestion!.explanation;
    }

    setState(() {
      _showingResults = true;
      _wasAnswerCorrect = false;
      _pointsEarned = 0;
    });

    HapticFeedback.mediumImpact();

    // Show results for 3 seconds before next question
    Timer(const Duration(seconds: 3), () {
      if (mounted && !_hasAnswered) {
        // Move to waiting state for next question
        setState(() => _showingResults = false);
      }
    });
  }

  void _showAnswerResults() {
    if (_currentQuestion == null) return;

    // Check if answer was correct and calculate points
    _wasAnswerCorrect = _currentQuestion!.isAnswerCorrect(_selectedAnswer);
    _correctAnswer = _getCorrectAnswerForDisplay();
    _explanation = _currentQuestion!.explanation;

    // Calculate points earned (this will be updated by the service, but we show immediate feedback)
    if (_wasAnswerCorrect) {
      _pointsEarned = _currentQuestion!.points;
      HapticFeedback.heavyImpact();
    } else {
      _pointsEarned = 0;
      HapticFeedback.mediumImpact();
    }

    setState(() => _showingResults = true);

    // Show results for 3 seconds before moving to next question
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showingResults = false);
      }
    });
  }

  dynamic _getCorrectAnswerForDisplay() {
    if (_currentQuestion == null) return null;

    switch (_currentQuestion!.type) {
      case QuestionType.multipleChoice:
      case QuestionType.trueFalse:
        return _currentQuestion!.correctOptionIndex;
      case QuestionType.shortAnswer:
        return _currentQuestion!.acceptableAnswers.isNotEmpty
            ? _currentQuestion!.acceptableAnswers.first
            : null;
    }
  }

  Future<void> _submitAnswer() async {
    if (_hasAnswered ||
        _participantId == null ||
        _currentQuestion == null ||
        _selectedAnswer == null) {
      return;
    }

    try {
      HapticFeedback.lightImpact();

      final timeToAnswer = _questionStartTime != null
          ? DateTime.now().difference(_questionStartTime!).inMilliseconds
          : 0;

      final success = await _liveQuizService.submitAnswer(
        quizId: widget.quizId,
        questionId: _currentQuestion!.id,
        participantId: _participantId!,
        questionIndex: _currentQuestion!.orderIndex,
        answer: _selectedAnswer,
        timeToAnswer: timeToAnswer,
      );

      if (success) {
        setState(() => _hasAnswered = true);

        // Don't cancel countdown timer yet - let it run to show results
        _showSuccess('Answer submitted!');

        // If time is almost up, show results immediately
        if (_timeRemaining <= 2) {
          _showAnswerResults();
        }
      } else {
        _showError('Failed to submit answer');
      }
    } catch (e) {
      _showError('Error submitting answer: $e');
    }
  }

  void _showError(String message) {
    ShowToast().showNormalToast(msg: message);
  }

  void _showSuccess(String message) {
    ShowToast().showNormalToast(msg: message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: _isJoining
            ? _buildJoiningScreen()
            : FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      _buildHeader(),
                      Expanded(child: _buildContent()),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildJoiningScreen() {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Connection Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Unable to join the quiz',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _isJoining = true;
                    _errorMessage = null;
                  });
                  _joinQuiz();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF667EEA),
                  ),
                  strokeWidth: 3,
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.quiz,
                  color: Color(0xFF667EEA),
                  size: 30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Joining Live Quiz...',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Connecting you to the live quiz.\nThis should only take a moment.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
              backgroundColor: Color(0xFFE5E7EB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _showLeaveConfirmation(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _quiz?.title ?? 'Live Quiz',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _participant?.displayName ?? 'Participant',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Connection status indicator
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _isConnected ? _pulseAnimation.value : 1.0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _isConnected 
                                      ? const Color(0xFF10B981) 
                                      : Colors.orange,
                                  shape: BoxShape.circle,
                                  boxShadow: _isConnected ? [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.5),
                                      spreadRadius: 2,
                                      blurRadius: 4,
                                    ),
                                  ] : [],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isConnected ? 'Live' : 'Reconnecting',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_quiz?.isLive == true && _timeRemaining > 0)
                _buildCountdownTimer(),
            ],
          ),
          if (_participant != null) ...[
            const SizedBox(height: 16),
            _buildScoreCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildCountdownTimer() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _timeRemaining <= 10 ? _pulseAnimation.value : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _timeRemaining <= 10
                  ? Colors.red.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer,
                  color: _timeRemaining <= 10 ? Colors.red : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '$_timeRemaining',
                  style: TextStyle(
                    color: _timeRemaining <= 10 ? Colors.red : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScoreCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_participant?.currentScore ?? 0}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Score',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_participant?.currentRank ?? '-'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Rank',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_participant?.correctAnswers ?? 0}/${_participant?.questionsAnswered ?? 0}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Correct',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_quiz == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_quiz!.isDraft) {
      return _buildWaitingScreen(
        'Quiz hasn\'t started yet',
        'Waiting for host to begin...',
      );
    }

    if (_quiz!.isEnded) {
      return _buildFinalResults();
    }

    if (_quiz!.isPaused) {
      return _buildWaitingScreen(
        'Quiz Paused',
        'Waiting for host to resume...',
      );
    }

    if (!_quiz!.hasCurrentQuestion || _currentQuestion == null) {
      return _buildWaitingScreen('Loading...', 'Preparing next question...');
    }

    if (_showingResults) {
      return _buildResultsScreen();
    }

    if (_hasAnswered) {
      return _buildAnswerSubmittedScreen();
    }

    return _buildQuestionScreen();
  }

  Widget _buildWaitingScreen(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF667EEA).withValues(alpha: 0.2),
                          const Color(0xFF764BA2).withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                          spreadRadius: 2,
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.hourglass_empty,
                      color: Color(0xFF667EEA),
                      size: 50,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 17,
                  color: Colors.grey.withValues(alpha: 0.8),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
                backgroundColor: const Color(0xFFE5E7EB),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Stay connected...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildQuestionCard(),
                const SizedBox(height: 24),
                Expanded(child: _buildAnswerOptions()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildQuestionCard() {
    if (_currentQuestion == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Question ${(_currentQuestion!.orderIndex) + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_currentQuestion!.points} pts',
                  style: const TextStyle(
                    color: Color(0xFF667EEA),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _currentQuestion!.question,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerOptions() {
    if (_currentQuestion == null) return const SizedBox();

    switch (_currentQuestion!.type) {
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceOptions();
      case QuestionType.trueFalse:
        return _buildTrueFalseOptions();
      case QuestionType.shortAnswer:
        return _buildShortAnswerInput();
    }
  }

  Widget _buildMultipleChoiceOptions() {
    return Column(
      children: _currentQuestion!.options.asMap().entries.map((entry) {
        final index = entry.key;
        final option = entry.value;
        final isSelected = _selectedAnswer == index;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () => setState(() => _selectedAnswer = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF667EEA).withValues(alpha: 0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF667EEA)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    spreadRadius: 0,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF667EEA)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF667EEA)
                            : Colors.grey.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Center(
                            child: Text(
                              String.fromCharCode(65 + index), // A, B, C, D
                              style: TextStyle(
                                color: Colors.grey.withValues(alpha: 0.7),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF667EEA)
                            : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTrueFalseOptions() {
    if (_showingResults) {
      return _buildTrueFalseResults();
    }

    return Column(
      children: [
        _buildTrueFalseOption('True', 0, Icons.check_circle),
        const SizedBox(height: 16),
        _buildTrueFalseOption('False', 1, Icons.cancel),
      ],
    );
  }

  Widget _buildTrueFalseOption(String label, int value, IconData icon) {
    final isSelected = _selectedAnswer == value;

    return GestureDetector(
      onTap: _hasAnswered
          ? null
          : () => setState(() => _selectedAnswer = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected
              ? (value == 0
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : Colors.red.withValues(alpha: 0.15))
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (value == 0 ? const Color(0xFF10B981) : Colors.red)
                : Colors.grey.withValues(alpha: 0.2),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? (value == 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2))
                  : Colors.black.withValues(alpha: 0.04),
              spreadRadius: 0,
              blurRadius: isSelected ? 16 : 8,
              offset: Offset(0, isSelected ? 6 : 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? (value == 0 ? const Color(0xFF10B981) : Colors.red)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? Colors.white
                    : Colors.grey.withValues(alpha: 0.6),
                size: 28,
              ),
            ),
            const SizedBox(width: 20),
            Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? (value == 0 ? const Color(0xFF10B981) : Colors.red)
                    : const Color(0xFF1A1A1A),
              ),
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(left: 16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: value == 0
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Selected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: value == 0 ? const Color(0xFF10B981) : Colors.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortAnswerInput() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Type your answer:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _textAnswerController,
            onChanged: (value) =>
                setState(() => _selectedAnswer = value.trim()),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter your answer here...',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF667EEA),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tip: Be specific and check your spelling!',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    if (_showingResults) {
      return Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Next question coming up...',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final canSubmit =
        _selectedAnswer != null && _timeRemaining > 0 && !_hasAnswered;

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: canSubmit
            ? const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              )
            : LinearGradient(
                colors: [
                  Colors.grey.withValues(alpha: 0.3),
                  Colors.grey.withValues(alpha: 0.3),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: canSubmit
            ? [
                BoxShadow(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                  spreadRadius: 0,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canSubmit ? _submitAnswer : null,
          child: Center(
            child: Text(
              _hasAnswered ? 'Answer Submitted' : 'Submit Answer',
              style: TextStyle(
                color: canSubmit
                    ? Colors.white
                    : Colors.grey.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildResultsHeader(),
                  const SizedBox(height: 24),
                  _buildAnswerResults(),
                  if (_explanation?.isNotEmpty == true) ...[
                    const SizedBox(height: 24),
                    _buildExplanationCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildPointsEarnedCard(),
                ],
              ),
            ),
          ),
          if (_quiz?.showLeaderboard == true) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: LiveLeaderboardWidget(quizId: widget.quizId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsHeader() {
    return AnimatedBuilder(
      animation: _celebrationAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _celebrationAnimation.value,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _wasAnswerCorrect
                  ? const Color(0xFF10B981).withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(60),
              border: Border.all(
                color: _wasAnswerCorrect ? const Color(0xFF10B981) : Colors.red,
                width: 3,
              ),
            ),
            child: Icon(
              _wasAnswerCorrect ? Icons.check_circle : Icons.cancel,
              color: _wasAnswerCorrect ? const Color(0xFF10B981) : Colors.red,
              size: 60,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnswerResults() {
    if (_currentQuestion == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _wasAnswerCorrect ? '🎉 Correct!' : '❌ Incorrect',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _wasAnswerCorrect ? const Color(0xFF10B981) : Colors.red,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentQuestion!.question,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Show answers based on question type
          if (_currentQuestion!.type == QuestionType.multipleChoice)
            _buildMultipleChoiceResults()
          else if (_currentQuestion!.type == QuestionType.trueFalse)
            _buildTrueFalseResults()
          else if (_currentQuestion!.type == QuestionType.shortAnswer)
            _buildShortAnswerResults(),
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceResults() {
    return Column(
      children: _currentQuestion!.options.asMap().entries.map((entry) {
        final index = entry.key;
        final option = entry.value;
        final isUserAnswer = _selectedAnswer == index;
        final isCorrectAnswer = _correctAnswer == index;

        Color backgroundColor;
        Color borderColor;
        Color textColor;
        Widget? leadingIcon;

        if (isCorrectAnswer) {
          backgroundColor = const Color(0xFF10B981).withValues(alpha: 0.1);
          borderColor = const Color(0xFF10B981);
          textColor = const Color(0xFF10B981);
          leadingIcon = Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 16),
          );
        } else if (isUserAnswer) {
          backgroundColor = Colors.red.withValues(alpha: 0.1);
          borderColor = Colors.red;
          textColor = Colors.red;
          leadingIcon = Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 16),
          );
        } else {
          backgroundColor = Colors.grey.withValues(alpha: 0.05);
          borderColor = Colors.grey.withValues(alpha: 0.3);
          textColor = Colors.grey;
          leadingIcon = Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                String.fromCharCode(65 + index), // A, B, C, D
                style: TextStyle(
                  color: Colors.grey.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: (isCorrectAnswer || isUserAnswer)
                  ? [
                      BoxShadow(
                        color: borderColor.withValues(alpha: 0.2),
                        spreadRadius: 0,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              children: [
                leadingIcon,
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                if (isUserAnswer && !isCorrectAnswer)
                  const Text(
                    'Your Answer',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (isCorrectAnswer)
                  const Text(
                    'Correct Answer',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTrueFalseResults() {
    return Column(
      children: [
        _buildTrueFalseResultOption('True', 0, Icons.check_circle),
        const SizedBox(height: 12),
        _buildTrueFalseResultOption('False', 1, Icons.cancel),
      ],
    );
  }

  Widget _buildTrueFalseResultOption(String label, int value, IconData icon) {
    final isUserAnswer = _selectedAnswer == value;
    final isCorrectAnswer = _correctAnswer == value;

    Color backgroundColor;
    Color borderColor;
    Color textColor;

    if (isCorrectAnswer) {
      backgroundColor = const Color(0xFF10B981).withValues(alpha: 0.1);
      borderColor = const Color(0xFF10B981);
      textColor = const Color(0xFF10B981);
    } else if (isUserAnswer) {
      backgroundColor = Colors.red.withValues(alpha: 0.1);
      borderColor = Colors.red;
      textColor = Colors.red;
    } else {
      backgroundColor = Colors.grey.withValues(alpha: 0.05);
      borderColor = Colors.grey.withValues(alpha: 0.3);
      textColor = Colors.grey;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: (isCorrectAnswer || isUserAnswer)
            ? [
                BoxShadow(
                  color: borderColor.withValues(alpha: 0.2),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          Icon(
            isCorrectAnswer
                ? Icons.check_circle
                : isUserAnswer
                ? Icons.cancel
                : icon,
            color: textColor,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          if (isUserAnswer && !isCorrectAnswer)
            const Text(
              'Your Answer',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            )
          else if (isCorrectAnswer)
            const Text(
              'Correct',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF10B981),
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShortAnswerResults() {
    final userAnswer = _selectedAnswer?.toString() ?? 'No answer provided';
    final correctAnswer = _correctAnswer?.toString() ?? 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User's answer
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _wasAnswerCorrect
                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _wasAnswerCorrect ? const Color(0xFF10B981) : Colors.red,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Answer:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _wasAnswerCorrect
                      ? const Color(0xFF10B981)
                      : Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                userAnswer,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _wasAnswerCorrect
                      ? const Color(0xFF10B981)
                      : Colors.red,
                ),
              ),
            ],
          ),
        ),
        if (!_wasAnswerCorrect) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Correct Answer:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  correctAnswer,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExplanationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF667EEA).withValues(alpha: 0.1),
            const Color(0xFF764BA2).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lightbulb,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Explanation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667EEA),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _explanation!,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsEarnedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _wasAnswerCorrect
              ? [
                  const Color(0xFF10B981).withValues(alpha: 0.1),
                  const Color(0xFF059669).withValues(alpha: 0.05),
                ]
              : [
                  Colors.grey.withValues(alpha: 0.1),
                  Colors.grey.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _wasAnswerCorrect
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            _wasAnswerCorrect ? Icons.emoji_events : Icons.sentiment_neutral,
            color: _wasAnswerCorrect ? const Color(0xFF10B981) : Colors.grey,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            '${_pointsEarned} Points',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _wasAnswerCorrect ? const Color(0xFF10B981) : Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _wasAnswerCorrect ? 'Well done!' : 'Better luck next time!',
            style: TextStyle(
              fontSize: 14,
              color: (_wasAnswerCorrect ? const Color(0xFF10B981) : Colors.grey)
                  .withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerSubmittedScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _celebrationAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _celebrationAnimation.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(60),
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Color(0xFF667EEA),
                          size: 60,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Answer Submitted!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Waiting for time to run out...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildSelectedAnswerPreview(),
              ],
            ),
          ),
          if (_quiz?.showLeaderboard == true) ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 300,
              child: LiveLeaderboardWidget(quizId: widget.quizId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedAnswerPreview() {
    if (_currentQuestion == null || _selectedAnswer == null)
      return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF667EEA).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Answer:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF667EEA),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getSelectedAnswerText(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  String _getSelectedAnswerText() {
    if (_currentQuestion == null || _selectedAnswer == null) return '';

    switch (_currentQuestion!.type) {
      case QuestionType.multipleChoice:
        final index = _selectedAnswer as int;
        if (index >= 0 && index < _currentQuestion!.options.length) {
          return '${String.fromCharCode(65 + index)}. ${_currentQuestion!.options[index]}';
        }
        return 'Unknown option';
      case QuestionType.trueFalse:
        return _selectedAnswer == 0 ? 'True' : 'False';
      case QuestionType.shortAnswer:
        return _selectedAnswer.toString();
    }
  }

  Widget _buildFinalResults() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Icon(
              Icons.emoji_events,
              color: Color(0xFF667EEA),
              size: 50,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Quiz Complete!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          if (_participant != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    spreadRadius: 0,
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Final Score',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_participant!.currentScore}',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF667EEA),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatItem(
                        'Final Rank',
                        '#${_participant!.currentRank ?? '-'}',
                      ),
                      _buildStatItem('Accuracy', _participant!.accuracyDisplay),
                      _buildStatItem(
                        'Correct',
                        '${_participant!.correctAnswers}/${_participant!.questionsAnswered}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_quiz?.showLeaderboard == true) ...[
            Expanded(child: LiveLeaderboardWidget(quizId: widget.quizId)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  void _showLeaveConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Quiz'),
        content: const Text(
          'Are you sure you want to leave this live quiz? You won\'t be able to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Leave quiz
              if (_participantId != null) {
                _liveQuizService.leaveQuiz(widget.quizId, _participantId!);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}
