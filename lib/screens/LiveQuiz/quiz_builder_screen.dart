import 'package:flutter/material.dart';
import 'package:attendus/models/quiz_question_model.dart';
import 'package:attendus/models/live_quiz_model.dart';
import 'package:attendus/Services/live_quiz_service.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/screens/LiveQuiz/quiz_host_screen.dart';

class QuizBuilderScreen extends StatefulWidget {
  final String eventId;
  final String? existingQuizId;

  const QuizBuilderScreen({
    super.key,
    required this.eventId,
    this.existingQuizId,
  });

  @override
  State<QuizBuilderScreen> createState() => _QuizBuilderScreenState();
}

class _QuizBuilderScreenState extends State<QuizBuilderScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _liveQuizService = LiveQuizService();

  // Controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Quiz Settings
  int _timePerQuestion = 30;
  bool _autoAdvance = true;
  bool _showLeaderboard = true;
  bool _allowAnonymous = true;
  int _maxParticipants = 1000;

  // Questions Management
  List<QuizQuestionModel> _questions = [];

  // UI State
  bool _isLoading = false;
  bool _isSaving = false;
  String? _quizId;

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadExistingQuiz();
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

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _loadExistingQuiz() async {
    setState(() => _isLoading = true);

    try {
      LiveQuizModel? quiz;

      // First try to load by existing quiz ID if provided
      if (widget.existingQuizId != null) {
        quiz = await _liveQuizService.getQuiz(widget.existingQuizId!);
      }

      // If no quiz found by ID or no ID provided, try to find by event ID
      if (quiz == null) {
        quiz = await _liveQuizService.getQuizByEventId(widget.eventId);
      }

      if (quiz != null) {
        _titleController.text = quiz.title;
        _descriptionController.text = quiz.description ?? '';
        _timePerQuestion = quiz.timePerQuestion;
        _autoAdvance = quiz.autoAdvance;
        _showLeaderboard = quiz.showLeaderboard;
        _allowAnonymous = quiz.allowAnonymous;
        _maxParticipants = quiz.maxParticipants;
        _quizId = quiz.id;

        final questions = await _liveQuizService.getQuestions(quiz.id);
        setState(() => _questions = questions);
      }
    } catch (e) {
      _showError('Failed to load quiz: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF667EEA),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading quiz builder...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              )
            : FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildQuizDetailsSection(),
                                const SizedBox(height: 24),
                                _buildQuizSettingsSection(),
                                const SizedBox(height: 24),
                                _buildQuestionsSection(),
                                const SizedBox(height: 32),
                                _buildActionButtons(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                child: Text(
                  widget.existingQuizId != null
                      ? 'Edit Live Quiz'
                      : 'Create Live Quiz',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              if (_questions.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_questions.length} Question${_questions.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Design an interactive quiz experience for your event',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuizDetailsSection() {
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
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.quiz,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Quiz Details',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _titleController,
            label: 'Quiz Title',
            hint: 'Enter a catchy quiz title',
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a quiz title';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _descriptionController,
            label: 'Description (Optional)',
            hint: 'Brief description of what this quiz is about',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildQuizSettingsSection() {
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
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.settings,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Quiz Settings',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Time per question
          _buildSettingRow(
            'Time per Question',
            '${_timePerQuestion}s',
            () => _showTimePickerDialog(),
          ),
          const SizedBox(height: 16),

          // Max participants
          _buildSettingRow(
            'Maximum Participants',
            _maxParticipants == 1000 ? 'Unlimited' : '$_maxParticipants',
            () => _showParticipantLimitDialog(),
          ),
          const SizedBox(height: 20),

          // Toggle settings
          _buildSwitchSetting(
            'Auto Advance Questions',
            'Automatically move to next question when time is up',
            _autoAdvance,
            (value) => setState(() => _autoAdvance = value),
          ),
          const SizedBox(height: 16),
          _buildSwitchSetting(
            'Show Live Leaderboard',
            'Participants can see their ranking in real-time',
            _showLeaderboard,
            (value) => setState(() => _showLeaderboard = value),
          ),
          const SizedBox(height: 16),
          _buildSwitchSetting(
            'Allow Anonymous Participation',
            'Users can join without signing in',
            _allowAnonymous,
            (value) => setState(() => _allowAnonymous = value),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsSection() {
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
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.help_outline,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Questions',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _addNewQuestion(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Question'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_questions.isEmpty)
            _buildEmptyQuestionsState()
          else
            ..._questions.asMap().entries.map((entry) {
              final index = entry.key;
              final question = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < _questions.length - 1 ? 16 : 0,
                ),
                child: _buildQuestionCard(question, index),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildEmptyQuestionsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(32),
            ),
            child: const Icon(
              Icons.quiz_outlined,
              color: Color(0xFF667EEA),
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Questions Yet',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontSize: 18,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first question to get started.\nYou can create multiple choice, true/false, or short answer questions.',
            style: TextStyle(
              color: Colors.grey.withValues(alpha: 0.7),
              fontSize: 14,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _addNewQuestion(),
            icon: const Icon(Icons.add),
            label: const Text('Add First Question'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(QuizQuestionModel question, int index) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${question.typeDisplayName} • ${question.points} pts • ${question.timeLimit}s',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _editQuestion(index);
                      break;
                    case 'duplicate':
                      _duplicateQuestion(index);
                      break;
                    case 'delete':
                      _deleteQuestion(index);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Row(
                      children: [
                        Icon(Icons.copy, size: 18),
                        SizedBox(width: 8),
                        Text('Duplicate'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (question.hasImage) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image, size: 14, color: const Color(0xFF667EEA)),
                  const SizedBox(width: 4),
                  const Text(
                    'Has Image',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF667EEA),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Save Draft / Update Button
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                spreadRadius: 0,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _isSaving ? null : _saveQuiz,
              child: Center(
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.existingQuizId != null
                            ? 'Update Quiz'
                            : 'Save Quiz',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
              ),
            ),
          ),
        ),

        if (_quizId != null && _questions.isNotEmpty) ...[
          const SizedBox(height: 16),
          // Preview & Host Button
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF667EEA), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _hostQuiz(),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_circle_outline,
                        color: Color(0xFF667EEA),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Preview & Host Quiz',
                        style: TextStyle(
                          color: Color(0xFF667EEA),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.withValues(alpha: 0.6),
              fontSize: 14,
            ),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: maxLines > 1 ? 16 : 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingRow(String title, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF667EEA),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Color(0xFF667EEA),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchSetting(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF667EEA),
        ),
      ],
    );
  }

  void _showTimePickerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Time per Question'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [10, 15, 20, 30, 45, 60, 90, 120].map((seconds) {
            return ListTile(
              title: Text('${seconds} seconds'),
              leading: Radio<int>(
                value: seconds,
                groupValue: _timePerQuestion,
                onChanged: (value) {
                  setState(() => _timePerQuestion = value!);
                  Navigator.pop(context);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showParticipantLimitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maximum Participants'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [50, 100, 250, 500, 1000].map((limit) {
            return ListTile(
              title: Text(limit == 1000 ? 'Unlimited' : '$limit participants'),
              leading: Radio<int>(
                value: limit,
                groupValue: _maxParticipants,
                onChanged: (value) {
                  setState(() => _maxParticipants = value!);
                  Navigator.pop(context);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _addNewQuestion() async {
    // Save quiz details first to get a quizId if it's a new quiz
    final quizId = _quizId ?? await _handleQuizSave();
    if (quizId == null) return;

    final newQuestion = await Navigator.push<QuizQuestionModel>(
      context,
      MaterialPageRoute(
        builder: (context) => QuestionEditorScreen(
          onSave: (question) => Navigator.pop(context, question),
        ),
      ),
    );

    if (newQuestion != null) {
      setState(() => _isSaving = true);
      try {
        final questionToSave = newQuestion.copyWith(
          quizId: quizId,
          orderIndex: _questions.length,
        );
        final questionId = await _liveQuizService.addQuestion(questionToSave);

        if (questionId != null) {
          setState(() {
            _questions.add(questionToSave.copyWith(id: questionId));
          });
          _showSuccess('Question added successfully!');
        } else {
          throw Exception('Failed to get question ID back from service.');
        }
      } catch (e) {
        _showError('Failed to save new question: $e');
      } finally {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _editQuestion(int index) async {
    final updatedQuestion = await Navigator.push<QuizQuestionModel>(
      context,
      MaterialPageRoute(
        builder: (context) => QuestionEditorScreen(
          existingQuestion: _questions[index],
          onSave: (question) => Navigator.pop(context, question),
        ),
      ),
    );

    if (updatedQuestion != null) {
      setState(() => _isSaving = true);
      try {
        final questionToSave = updatedQuestion.copyWith(orderIndex: index);
        final success = await _liveQuizService.updateQuestion(
          questionToSave.id,
          questionToSave.toJson(),
        );

        if (success) {
          setState(() {
            _questions[index] = questionToSave;
          });
          _showSuccess('Question updated successfully!');
        } else {
          throw Exception('Update operation failed.');
        }
      } catch (e) {
        _showError('Failed to update question: $e');
      } finally {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _duplicateQuestion(int index) async {
    setState(() => _isSaving = true);
    try {
      final original = _questions[index];
      final duplicatedQuestion = original.copyWith(
        id: '', // New ID will be generated by Firestore
        orderIndex: index + 1,
        question: '${original.question} (Copy)',
      );

      final newQuestionId = await _liveQuizService.addQuestion(
        duplicatedQuestion,
      );

      if (newQuestionId != null) {
        setState(() {
          _questions.insert(
            index + 1,
            duplicatedQuestion.copyWith(id: newQuestionId),
          );
          // Update order indices for subsequent questions
          for (int i = index + 2; i < _questions.length; i++) {
            final question = _questions[i];
            final updatedQuestion = question.copyWith(orderIndex: i);
            _questions[i] = updatedQuestion;
            // Also update in Firestore
            _liveQuizService.updateQuestion(updatedQuestion.id, {
              'orderIndex': i,
            });
          }
        });
        _showSuccess('Question duplicated!');
      } else {
        throw Exception('Failed to save duplicated question.');
      }
    } catch (e) {
      _showError('Failed to duplicate question: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _deleteQuestion(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Question'),
        content: const Text(
          'Are you sure you want to delete this question? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog first
              setState(() => _isSaving = true);
              try {
                final questionToDelete = _questions[index];
                final success = await _liveQuizService.deleteQuestion(
                  questionToDelete.id,
                  questionToDelete.quizId,
                );

                if (success) {
                  setState(() {
                    _questions.removeAt(index);
                    // Update order indices for subsequent questions
                    for (int i = index; i < _questions.length; i++) {
                      final question = _questions[i];
                      final updatedQuestion = question.copyWith(orderIndex: i);
                      _questions[i] = updatedQuestion;
                      _liveQuizService.updateQuestion(updatedQuestion.id, {
                        'orderIndex': i,
                      });
                    }
                  });
                  _showSuccess('Question deleted!');
                } else {
                  throw Exception('Delete operation failed.');
                }
              } catch (e) {
                _showError('Failed to delete question: $e');
              } finally {
                setState(() => _isSaving = false);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<String?> _handleQuizSave() async {
    if (!_formKey.currentState!.validate()) return null;

    setState(() => _isSaving = true);

    String? quizId;

    try {
      if (widget.existingQuizId != null || _quizId != null) {
        quizId = widget.existingQuizId ?? _quizId!;
        await _liveQuizService.updateQuiz(quizId, {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'timePerQuestion': _timePerQuestion,
          'autoAdvance': _autoAdvance,
          'showLeaderboard': _showLeaderboard,
          'allowAnonymous': _allowAnonymous,
          'maxParticipants': _maxParticipants,
        });
      } else {
        final newQuizId = await _liveQuizService.createLiveQuiz(
          eventId: widget.eventId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          timePerQuestion: _timePerQuestion,
          autoAdvance: _autoAdvance,
          showLeaderboard: _showLeaderboard,
          allowAnonymous: _allowAnonymous,
          maxParticipants: _maxParticipants,
        );

        if (newQuizId == null) {
          throw Exception('Failed to create quiz');
        }

        quizId = newQuizId;
        setState(() {
          _quizId = quizId;
        });
      }
      return quizId;
    } catch (e) {
      _showError('Failed to save quiz details: $e');
      return null;
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveQuiz() async {
    if (_questions.isEmpty) {
      _showError('Please add at least one question before saving.');
      return;
    }
    final quizId = await _handleQuizSave();
    if (quizId != null) {
      _showSuccess('Quiz details saved successfully!');
    }
  }

  void _hostQuiz() {
    if (_quizId == null) {
      _showError('Please save the quiz first');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => QuizHostScreen(quizId: _quizId!)),
    );
  }
}

// Question Editor Screen - Implementation continues in a separate file for maintainability
class QuestionEditorScreen extends StatefulWidget {
  final QuizQuestionModel? existingQuestion;
  final Function(QuizQuestionModel) onSave;

  const QuestionEditorScreen({
    super.key,
    this.existingQuestion,
    required this.onSave,
  });

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _explanationController = TextEditingController();

  QuestionType _selectedType = QuestionType.multipleChoice;
  List<String> _options = ['', '', '', ''];
  int _correctOptionIndex = 0;
  List<String> _acceptableAnswers = [''];
  bool _caseSensitive = false;
  int _timeLimit = 30;
  int _points = 100;

  @override
  void initState() {
    super.initState();
    _loadExistingQuestion();
  }

  void _loadExistingQuestion() {
    final question = widget.existingQuestion;
    if (question == null) return;

    _questionController.text = question.question;
    _explanationController.text = question.explanation ?? '';
    _selectedType = question.type;
    _timeLimit = question.timeLimit;
    _points = question.points;

    switch (question.type) {
      case QuestionType.multipleChoice:
        _options = List.from(question.options);
        while (_options.length < 4) _options.add('');
        _correctOptionIndex = question.correctOptionIndex ?? 0;
        break;
      case QuestionType.trueFalse:
        _correctOptionIndex = question.correctOptionIndex ?? 0;
        break;
      case QuestionType.shortAnswer:
        _acceptableAnswers = List.from(question.acceptableAnswers);
        if (_acceptableAnswers.isEmpty) _acceptableAnswers.add('');
        _caseSensitive = question.caseSensitive;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF667EEA),
        title: Text(
          widget.existingQuestion != null ? 'Edit Question' : 'Add Question',
        ),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: true,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24 + bottomPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuestionTypeSelector(),
                const SizedBox(height: 24),
                _buildQuestionInput(),
                const SizedBox(height: 24),
                _buildAnswerSection(),
                const SizedBox(height: 24),
                _buildQuestionSettings(),
                const SizedBox(height: 32),
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionTypeSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Question Type',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          ...QuestionType.values.map((type) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Radio<QuestionType>(
                  value: type,
                  groupValue: _selectedType,
                  onChanged: (value) => setState(() => _selectedType = value!),
                  activeColor: const Color(0xFF667EEA),
                ),
                title: Text(_getTypeTitle(type)),
                subtitle: Text(_getTypeDescription(type)),
                contentPadding: EdgeInsets.zero,
                onTap: () => setState(() => _selectedType = type),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildQuestionInput() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Question',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _questionController,
            maxLines: 3,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a question';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: 'Enter your question here...',
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
        ],
      ),
    );
  }

  Widget _buildAnswerSection() {
    switch (_selectedType) {
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceAnswers();
      case QuestionType.trueFalse:
        return _buildTrueFalseAnswers();
      case QuestionType.shortAnswer:
        return _buildShortAnswerAnswers();
    }
  }

  Widget _buildMultipleChoiceAnswers() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Answer Options',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          ..._options.asMap().entries.map((entry) {
            final index = entry.key;
            final option = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Radio<int>(
                    value: index,
                    groupValue: _correctOptionIndex,
                    onChanged: (value) =>
                        setState(() => _correctOptionIndex = value!),
                    activeColor: const Color(0xFF667EEA),
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: option,
                      onChanged: (value) => _options[index] = value,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Option cannot be empty';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: 'Option ${index + 1}',
                        filled: true,
                        fillColor: _correctOptionIndex == index
                            ? const Color(0xFF667EEA).withValues(alpha: 0.1)
                            : const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _correctOptionIndex == index
                                ? const Color(0xFF667EEA)
                                : Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _correctOptionIndex == index
                                ? const Color(0xFF667EEA)
                                : Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF667EEA),
                            width: 2,
                          ),
                        ),
                      ),
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

  Widget _buildTrueFalseAnswers() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Correct Answer',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Radio<int>(
              value: 0,
              groupValue: _correctOptionIndex,
              onChanged: (value) =>
                  setState(() => _correctOptionIndex = value!),
              activeColor: const Color(0xFF667EEA),
            ),
            title: const Text('True'),
            onTap: () => setState(() => _correctOptionIndex = 0),
          ),
          ListTile(
            leading: Radio<int>(
              value: 1,
              groupValue: _correctOptionIndex,
              onChanged: (value) =>
                  setState(() => _correctOptionIndex = value!),
              activeColor: const Color(0xFF667EEA),
            ),
            title: const Text('False'),
            onTap: () => setState(() => _correctOptionIndex = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildShortAnswerAnswers() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Acceptable Answers',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _acceptableAnswers.add(''));
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Answer'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._acceptableAnswers.asMap().entries.map((entry) {
            final index = entry.key;
            final answer = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: answer,
                      onChanged: (value) => _acceptableAnswers[index] = value,
                      validator: (value) {
                        if (index == 0 &&
                            (value == null || value.trim().isEmpty)) {
                          return 'At least one answer is required';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: 'Acceptable answer ${index + 1}',
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF667EEA),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_acceptableAnswers.length > 1)
                    IconButton(
                      onPressed: () {
                        setState(() => _acceptableAnswers.removeAt(index));
                      },
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                    ),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Case Sensitive'),
            subtitle: const Text('Answers must match exact capitalization'),
            value: _caseSensitive,
            onChanged: (value) => setState(() => _caseSensitive = value),
            activeThumbColor: const Color(0xFF667EEA),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionSettings() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Question Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Time Limit (seconds)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _timeLimit,
                      isDense: true,
                      onChanged: (value) => setState(() => _timeLimit = value!),
                      items: [10, 15, 20, 30, 45, 60, 90, 120].map((time) {
                        return DropdownMenuItem(
                          value: time,
                          child: Text('$time seconds'),
                        );
                      }).toList(),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF667EEA),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Points',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _points,
                      isDense: true,
                      onChanged: (value) => setState(() => _points = value!),
                      items: [50, 100, 150, 200, 250, 300, 500].map((points) {
                        return DropdownMenuItem(
                          value: points,
                          child: Text('$points pts'),
                        );
                      }).toList(),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF667EEA),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _explanationController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Explanation (Optional)',
              hintText: 'Provide an explanation for the correct answer...',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF667EEA),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
            spreadRadius: 0,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _saveQuestion,
          child: Center(
            child: Text(
              widget.existingQuestion != null
                  ? 'Update Question'
                  : 'Save Question',
              style: const TextStyle(
                color: Colors.white,
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

  String _getTypeTitle(QuestionType type) {
    switch (type) {
      case QuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuestionType.trueFalse:
        return 'True/False';
      case QuestionType.shortAnswer:
        return 'Short Answer';
    }
  }

  String _getTypeDescription(QuestionType type) {
    switch (type) {
      case QuestionType.multipleChoice:
        return 'Participants choose from 4 options';
      case QuestionType.trueFalse:
        return 'Simple true or false question';
      case QuestionType.shortAnswer:
        return 'Participants type their answer';
    }
  }

  void _saveQuestion() {
    if (!_formKey.currentState!.validate()) return;

    // Clean up acceptable answers for short answer questions
    if (_selectedType == QuestionType.shortAnswer) {
      _acceptableAnswers = _acceptableAnswers
          .where((answer) => answer.trim().isNotEmpty)
          .toList();

      if (_acceptableAnswers.isEmpty) {
        ShowToast().showNormalToast(
          msg: 'Please add at least one acceptable answer',
        );
        return;
      }
    }

    // Create question based on type
    QuizQuestionModel question;
    switch (_selectedType) {
      case QuestionType.multipleChoice:
        // Validate options
        final validOptions = _options
            .where((option) => option.trim().isNotEmpty)
            .toList();
        if (validOptions.length < 2) {
          ShowToast().showNormalToast(msg: 'Please provide at least 2 options');
          return;
        }

        question = QuizQuestionModel.multipleChoice(
          id: widget.existingQuestion?.id ?? '',
          quizId: widget.existingQuestion?.quizId ?? '',
          orderIndex: widget.existingQuestion?.orderIndex ?? 0,
          question: _questionController.text.trim(),
          options: validOptions,
          correctOptionIndex: _correctOptionIndex,
          explanation: _explanationController.text.trim().isEmpty
              ? null
              : _explanationController.text.trim(),
          timeLimit: _timeLimit,
          points: _points,
        );
        break;

      case QuestionType.trueFalse:
        question = QuizQuestionModel.trueFalse(
          id: widget.existingQuestion?.id ?? '',
          quizId: widget.existingQuestion?.quizId ?? '',
          orderIndex: widget.existingQuestion?.orderIndex ?? 0,
          question: _questionController.text.trim(),
          correctAnswer: _correctOptionIndex == 0,
          explanation: _explanationController.text.trim().isEmpty
              ? null
              : _explanationController.text.trim(),
          timeLimit: _timeLimit,
          points: _points,
        );
        break;

      case QuestionType.shortAnswer:
        question = QuizQuestionModel.shortAnswer(
          id: widget.existingQuestion?.id ?? '',
          quizId: widget.existingQuestion?.quizId ?? '',
          orderIndex: widget.existingQuestion?.orderIndex ?? 0,
          question: _questionController.text.trim(),
          acceptableAnswers: _acceptableAnswers,
          caseSensitive: _caseSensitive,
          explanation: _explanationController.text.trim().isEmpty
              ? null
              : _explanationController.text.trim(),
          timeLimit: _timeLimit,
          points: _points,
        );
        break;
    }

    widget.onSave(question);
  }
}
