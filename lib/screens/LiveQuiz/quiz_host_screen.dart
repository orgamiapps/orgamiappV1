import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/models/live_quiz_model.dart';
import 'package:attendus/models/quiz_question_model.dart';
import 'package:attendus/Services/live_quiz_service.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/screens/LiveQuiz/widgets/live_leaderboard_widget.dart';
import 'package:attendus/screens/LiveQuiz/widgets/quiz_waiting_lobby.dart';

class QuizHostScreen extends StatefulWidget {
  final String quizId;

  const QuizHostScreen({super.key, required this.quizId});

  @override
  State<QuizHostScreen> createState() => _QuizHostScreenState();
}

class _QuizHostScreenState extends State<QuizHostScreen>
    with TickerProviderStateMixin {
  final _liveQuizService = LiveQuizService();

  // Quiz State
  LiveQuizModel? _quiz;
  List<QuizQuestionModel> _questions = [];
  QuizQuestionModel? _currentQuestion;
  Map<String, dynamic> _quizStats = {};

  // UI State
  bool _isLoading = true;
  int _selectedTabIndex = 0;
  String? _errorMessage;
  bool _hasError = false;

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  // Streams
  StreamSubscription<LiveQuizModel>? _quizSubscription;
  StreamSubscription<List<QuizQuestionModel>>? _questionsSubscription;

  // Countdown Timer
  Timer? _countdownTimer;
  int _timeRemaining = 0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadQuizData();
    _setupStreams();
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
      duration: const Duration(milliseconds: 1200),
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

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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
    _countdownTimer?.cancel();
    _quizSubscription?.cancel();
    _questionsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadQuizData() async {
    try {
      // Add timeout to prevent infinite loading
      final results =
          await Future.wait([
            _liveQuizService.getQuiz(widget.quizId),
            _liveQuizService.getQuestions(widget.quizId),
            _liveQuizService.getQuizStats(widget.quizId),
          ]).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Loading timeout. Please check your connection.',
            ),
          );

      final quiz = results[0] as LiveQuizModel?;
      final questions = results[1] as List<QuizQuestionModel>;
      final stats = results[2] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _quiz = quiz;
          _questions = questions;
          _quizStats = stats;
          _isLoading = false;
          _hasError = false;
        });

        // Load current question if quiz is active
        if (quiz != null && quiz.hasCurrentQuestion) {
          _loadCurrentQuestion();
        }

        // Start countdown if quiz is live
        if (quiz != null && quiz.isLive) {
          _startCountdown();
        }
      }
    } catch (e) {
      Logger.error('Failed to load quiz data: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
        _showError('Failed to load quiz: ${e.toString()}');
      }
    }
  }

  void _setupStreams() {
    // Quiz state updates
    _quizSubscription = _liveQuizService.getQuizStream(widget.quizId).listen((
      quiz,
    ) {
      setState(() => _quiz = quiz);

      // Update current question if changed
      if (quiz.hasCurrentQuestion) {
        _loadCurrentQuestion();
      }

      // Update countdown
      if (quiz.isLive) {
        _startCountdown();
      } else {
        _countdownTimer?.cancel();
      }

      // Refresh stats
      _refreshStats();
    }, onError: (error) => _showError('Quiz stream error: $error'));

    // Questions updates
    _questionsSubscription = _liveQuizService
        .getQuestionsStream(widget.quizId)
        .listen((questions) {
          setState(() => _questions = questions);
        }, onError: (error) => _showError('Questions stream error: $error'));
  }

  Future<void> _loadCurrentQuestion() async {
    if (_quiz?.hasCurrentQuestion != true) {
      setState(() => _currentQuestion = null);
      return;
    }

    try {
      final question = await _liveQuizService.getCurrentQuestion(widget.quizId);
      setState(() => _currentQuestion = question);
    } catch (e) {
      _showError('Failed to load current question: $e');
    }
  }

  void _startCountdown() {
    if (_quiz?.timeRemainingForCurrentQuestion == null) return;

    _countdownTimer?.cancel();

    setState(() {
      _timeRemaining = _quiz!.timeRemainingForCurrentQuestion!.inSeconds;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() => _timeRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _refreshStats() async {
    try {
      final stats = await _liveQuizService.getQuizStats(widget.quizId);
      setState(() => _quizStats = stats);
    } catch (e) {
      _showError('Failed to refresh stats: $e');
    }
  }

  // Quiz Control Actions
  Future<void> _startQuiz() async {
    if (_questions.isEmpty) {
      _showError('Cannot start quiz without questions');
      return;
    }

    HapticFeedback.mediumImpact();
    final success = await _liveQuizService.startQuiz(widget.quizId);
    if (success) {
      _showSuccess('Quiz started! Participants can now join.');
    } else {
      _showError('Failed to start quiz');
    }
  }

  Future<void> _pauseQuiz() async {
    HapticFeedback.lightImpact();
    final success = await _liveQuizService.pauseQuiz(widget.quizId);
    if (success) {
      _showSuccess('Quiz paused');
    } else {
      _showError('Failed to pause quiz');
    }
  }

  Future<void> _resumeQuiz() async {
    HapticFeedback.lightImpact();
    final success = await _liveQuizService.resumeQuiz(widget.quizId);
    if (success) {
      _showSuccess('Quiz resumed');
    } else {
      _showError('Failed to resume quiz');
    }
  }

  Future<void> _nextQuestion() async {
    HapticFeedback.mediumImpact();
    final success = await _liveQuizService.nextQuestion(widget.quizId);
    if (success) {
      _showSuccess('Advanced to next question');
    } else {
      _showError('Failed to advance question');
    }
  }

  Future<void> _endQuiz() async {
    final confirmed = await _showEndQuizConfirmation();
    if (!confirmed) return;

    HapticFeedback.heavyImpact();
    final success = await _liveQuizService.endQuiz(widget.quizId);
    if (success) {
      _showSuccess('Quiz ended successfully!');
    } else {
      _showError('Failed to end quiz');
    }
  }

  Future<bool> _showEndQuizConfirmation() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('End Quiz'),
            content: const Text(
              'Are you sure you want to end this quiz? This action cannot be undone and all participants will see the final results.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('End Quiz'),
              ),
            ],
          ),
        ) ??
        false;
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
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF667EEA),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading quiz...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : _hasError
            ? _buildErrorState()
            : FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      _buildHeader(),
                      _buildControlPanel(),
                      Expanded(child: _buildTabView()),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildErrorState() {
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
              'Failed to Load Quiz',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An unexpected error occurred',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isLoading = true;
                });
                _loadQuizData();
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
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Quiz Host',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    Text(
                      _quiz?.title ?? 'Loading...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              _buildQuizStatusBadge(),
            ],
          ),
          const SizedBox(height: 20),
          _buildStatsRow(),
        ],
      ),
    );
  }

  Widget _buildQuizStatusBadge() {
    if (_quiz == null) return const SizedBox();

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (_quiz!.status) {
      case QuizStatus.draft:
        statusColor = Colors.orange;
        statusText = 'DRAFT';
        statusIcon = Icons.edit;
        break;
      case QuizStatus.live:
        statusColor = const Color(0xFF10B981);
        statusText = 'LIVE';
        statusIcon = Icons.live_tv;
        break;
      case QuizStatus.paused:
        statusColor = Colors.amber;
        statusText = 'PAUSED';
        statusIcon = Icons.pause;
        break;
      case QuizStatus.ended:
        statusColor = Colors.grey;
        statusText = 'ENDED';
        statusIcon = Icons.check_circle;
        break;
    }

    return AnimatedBuilder(
      animation: _quiz!.isLive ? _pulseAnimation : _fadeAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _quiz!.isLive ? _pulseAnimation.value : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _quiz!.isLive
                  ? [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.5),
                        spreadRadius: 0,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Participants',
            '${_quiz?.participantCount ?? 0}',
            Icons.people,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Progress',
            '${_quizStats['questionsAsked'] ?? 0}/${_questions.length}',
            Icons.quiz,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Accuracy',
            '${(_quizStats['averageAccuracy'] ?? 0.0).toStringAsFixed(1)}%',
            Icons.bar_chart,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      margin: const EdgeInsets.all(24),
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
        children: [
          if (_quiz?.isLive == true && _currentQuestion != null) ...[
            _buildCurrentQuestionHeader(),
            const SizedBox(height: 20),
          ],
          _buildControlButtons(),
        ],
      ),
    );
  }

  Widget _buildCurrentQuestionHeader() {
    if (_currentQuestion == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.topRight,
          colors: [
            const Color(0xFF667EEA).withValues(alpha: 0.1),
            const Color(0xFF764BA2).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Question ${(_currentQuestion!.orderIndex) + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              if (_timeRemaining > 0)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _timeRemaining <= 10 ? _pulseAnimation.value : 1.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _timeRemaining <= 10
                              ? Colors.red.withValues(alpha: 0.1)
                              : const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer,
                              size: 14,
                              color: _timeRemaining <= 10
                                  ? Colors.red
                                  : const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_timeRemaining}s',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _timeRemaining <= 10
                                    ? Colors.red
                                    : const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _currentQuestion!.question,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    if (_quiz == null) return const SizedBox();

    return Row(
      children: [
        if (_quiz!.isDraft) ...[
          Expanded(
            child: _buildActionButton(
              'Start Quiz',
              Icons.play_arrow,
              const Color(0xFF10B981),
              _startQuiz,
            ),
          ),
        ] else if (_quiz!.isLive) ...[
          Expanded(
            child: _buildActionButton(
              'Pause',
              Icons.pause,
              Colors.amber,
              _pauseQuiz,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              'Next Question',
              Icons.skip_next,
              const Color(0xFF667EEA),
              _nextQuestion,
              enabled: _quiz!.hasCurrentQuestion,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              'End Quiz',
              Icons.stop,
              Colors.red,
              _endQuiz,
            ),
          ),
        ] else if (_quiz!.isPaused) ...[
          Expanded(
            child: _buildActionButton(
              'Resume',
              Icons.play_arrow,
              const Color(0xFF10B981),
              _resumeQuiz,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              'End Quiz',
              Icons.stop,
              Colors.red,
              _endQuiz,
            ),
          ),
        ] else if (_quiz!.isEnded) ...[
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: const Center(
                child: Text(
                  'Quiz Completed',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed, {
    bool enabled = true,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withValues(alpha: 0.8)],
              )
            : LinearGradient(
                colors: [
                  Colors.grey.withValues(alpha: 0.3),
                  Colors.grey.withValues(alpha: 0.3),
                ],
              ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabView() {
    return Column(
      children: [
        // Only show tab selector if quiz is not in draft
        if (_quiz?.isDraft != true) _buildTabSelector(),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildTabSelector() {
    final tabs = ['Questions', 'Leaderboard', 'Analytics'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(4),
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
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isSelected = _selectedTabIndex == index;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTabIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF667EEA)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    tab,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    // Show waiting lobby for draft quizzes
    if (_quiz?.isDraft == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: QuizWaitingLobby(
          quizId: widget.quizId,
          quizTitle: _quiz?.title ?? 'Live Quiz',
        ),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _getTabContent(_selectedTabIndex),
      ),
    );
  }

  Widget _getTabContent(int index) {
    switch (index) {
      case 0:
        return _buildQuestionsTab();
      case 1:
        return _buildLeaderboardTab();
      case 2:
        return _buildAnalyticsTab();
      default:
        return const SizedBox();
    }
  }

  Widget _buildQuestionsTab() {
    if (_questions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No Questions Added',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Go back to the quiz builder to add questions',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final question = _questions[index];
        final isCurrent = _quiz?.currentQuestionIndex == index;
        final isPast = (_quiz?.currentQuestionIndex ?? -1) > index;

        return _buildQuestionListItem(question, index, isCurrent, isPast);
      },
    );
  }

  Widget _buildQuestionListItem(
    QuizQuestionModel question,
    int index,
    bool isCurrent,
    bool isPast,
  ) {
    Color borderColor;
    Color backgroundColor;
    Color textColor;

    if (isCurrent) {
      borderColor = const Color(0xFF10B981);
      backgroundColor = const Color(0xFF10B981).withValues(alpha: 0.1);
      textColor = const Color(0xFF10B981);
    } else if (isPast) {
      borderColor = Colors.grey.withValues(alpha: 0.3);
      backgroundColor = Colors.grey.withValues(alpha: 0.05);
      textColor = Colors.grey;
    } else {
      borderColor = const Color(0xFF667EEA).withValues(alpha: 0.3);
      backgroundColor = Colors.white;
      textColor = const Color(0xFF1A1A1A);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isCurrent ? 2 : 1),
          boxShadow: isCurrent
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
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCurrent
                    ? const Color(0xFF10B981)
                    : isPast
                    ? Colors.grey
                    : const Color(0xFF667EEA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: isCurrent
                    ? const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 18,
                      )
                    : isPast
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.question,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${question.typeDisplayName} • ${question.points} pts',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrent && _timeRemaining > 0) ...[
              const SizedBox(width: 12),
              CircularProgressIndicator(
                value: _timeRemaining / (_currentQuestion?.timeLimit ?? 30),
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(textColor),
                backgroundColor: textColor.withValues(alpha: 0.2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    return LiveLeaderboardWidget(
      quizId: widget.quizId,
      maxVisible: 20,
      showAnimation: _quiz?.isLive == true,
    );
  }

  Widget _buildAnalyticsTab() {
    return QuizAnalyticsWidget(
      quizId: widget.quizId,
      questions: _questions,
      stats: _quizStats,
    );
  }
}

// Simple inline QuizAnalyticsWidget to avoid circular imports
class QuizAnalyticsWidget extends StatelessWidget {
  final String quizId;
  final List<QuizQuestionModel> questions;
  final Map<String, dynamic> stats;

  const QuizAnalyticsWidget({
    super.key,
    required this.quizId,
    required this.questions,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewCards(),
          const SizedBox(height: 20),
          _buildQuestionTypeBreakdown(),
        ],
      ),
    );
  }

  Widget _buildOverviewCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Responses',
                '${stats['totalResponses'] ?? 0}',
                Icons.quiz,
                const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Correct Answers',
                '${stats['correctResponses'] ?? 0}',
                Icons.check_circle,
                const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Completion Rate',
                '${(stats['progress'] ?? 0.0).toStringAsFixed(1)}%',
                Icons.trending_up,
                const Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Questions Asked',
                '${stats['questionsAsked'] ?? 0}',
                Icons.help_outline,
                Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuestionTypeBreakdown() {
    final typeStats = _getQuestionTypeStats();

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
            'Question Types',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          ...typeStats.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getQuestionTypeColor(entry.key),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.value}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF667EEA),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Map<String, int> _getQuestionTypeStats() {
    final typeStats = <String, int>{};

    for (final question in questions) {
      final type = question.typeDisplayName;
      typeStats[type] = (typeStats[type] ?? 0) + 1;
    }

    return typeStats;
  }

  Color _getQuestionTypeColor(String type) {
    switch (type) {
      case 'Multiple Choice':
        return const Color(0xFF667EEA);
      case 'True/False':
        return const Color(0xFF10B981);
      case 'Short Answer':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
