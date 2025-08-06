import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';
import 'package:orgami/Screens/Events/Widget/AddQuestionPopup.dart';
import 'package:orgami/Screens/Events/CreateEventScreen.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class AddQuestionsToEventScreen extends StatefulWidget {
  final EventModel eventModel;
  final VoidCallback? onBackPressed;
  final Map<String, dynamic>? eventCreationData;

  const AddQuestionsToEventScreen({
    super.key,
    required this.eventModel,
    this.onBackPressed,
    this.eventCreationData,
  });

  @override
  State<AddQuestionsToEventScreen> createState() =>
      _AddQuestionsToEventScreenState();
}

class _AddQuestionsToEventScreenState extends State<AddQuestionsToEventScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();
  List<EventQuestionModel> questionsList = [];
  bool _isLoading = true;
  bool _showTemplates = false;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Pre-built question templates - Professional questions that event hosts actually want to ask
  final List<Map<String, dynamic>> _questionTemplates = [
    {
      'title': 'How did you hear about this event?',
      'category': 'Marketing',
      'icon': Icons.campaign,
      'color': Color(0xFF667EEA),
      'description': 'Track your marketing effectiveness',
    },
    {
      'title': 'What is your primary reason for attending today?',
      'category': 'Engagement',
      'icon': Icons.psychology,
      'color': Color(0xFF10B981),
      'description': 'Understand attendee motivations',
    },
    {
      'title': 'Do you have any dietary restrictions or allergies?',
      'category': 'Logistics',
      'icon': Icons.restaurant,
      'color': Color(0xFFFF9800),
      'description': 'Ensure proper catering arrangements',
    },
    {
      'title': 'Would you like to receive updates about future events?',
      'category': 'Communication',
      'icon': Icons.notifications,
      'color': Color(0xFF8B5CF6),
      'description': 'Build your email list',
    },
    {
      'title': 'What topics or sessions interest you most?',
      'category': 'Preferences',
      'icon': Icons.favorite,
      'color': Color(0xFFEF4444),
      'description': 'Tailor content to your audience',
    },
    {
      'title': 'How many people are you attending with?',
      'category': 'Logistics',
      'icon': Icons.people,
      'color': Color(0xFF06B6D4),
      'description': 'Plan seating and materials',
    },
    {
      'title': 'Do you require any accessibility accommodations?',
      'category': 'Accessibility',
      'icon': Icons.accessibility,
      'color': Color(0xFF059669),
      'description': 'Ensure inclusive experience',
    },
    {
      'title': 'What industry or field do you work in?',
      'category': 'Networking',
      'icon': Icons.business,
      'color': Color(0xFF7C3AED),
      'description': 'Facilitate meaningful connections',
    },
  ];

  Future<void> _getQuestions() async {
    setState(() {
      _isLoading = true;
    });

    await FirebaseFirestoreHelper()
        .getEventQuestions(eventId: widget.eventModel.id)
        .then((value) {
          setState(() {
            questionsList = value;
            _isLoading = false;
          });
        });
  }

  Future<void> _deleteQuestion(EventQuestionModel question) async {
    try {
      await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .doc(widget.eventModel.id)
          .collection(EventQuestionModel.firebaseKey)
          .doc(question.id)
          .delete();

      setState(() {
        questionsList.removeWhere((q) => q.id == question.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Question deleted successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete question'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _addTemplateQuestion(Map<String, dynamic> template) async {
    // During event creation, we don't have a real event ID yet
    // So we'll add the question to the local list and it will be saved when the event is created
    if (widget.eventModel.id.isEmpty) {
      // Create a temporary question for event creation flow
      EventQuestionModel newQuestion = EventQuestionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
        questionTitle: template['title'],
        required: false,
      );

      setState(() {
        questionsList.add(newQuestion);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Question "${template['title']}" added successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      // For existing events, save to Firestore
      String newId = FirebaseFirestore.instance
          .collection(EventQuestionModel.firebaseKey)
          .doc()
          .id;

      EventQuestionModel newQuestion = EventQuestionModel(
        id: newId,
        questionTitle: template['title'],
        required: false,
      );

      try {
        await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .doc(widget.eventModel.id)
            .collection(EventQuestionModel.firebaseKey)
            .doc(newQuestion.id)
            .set(newQuestion.toJson());

        setState(() {
          questionsList.add(newQuestion);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question "${template['title']}" added successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add question: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();

    // Show templates by default during event creation
    if (widget.eventModel.id.isEmpty) {
      _showTemplates = true;
    }

    _getQuestions();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FadeTransition(opacity: _fadeAnimation, child: _bodyView()),
      ),
      floatingActionButton: widget.eventModel.id.isEmpty
          ? null // Hide FAB during event creation, use bottom button instead
          : FloatingActionButton.extended(
              onPressed: () async {
                await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AddQuestionPopup(eventModel: widget.eventModel);
                  },
                ).then((newQuestion) {
                  if (newQuestion != null) {
                    setState(() {
                      questionsList.add(newQuestion);
                    });
                  }
                });
              },
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              elevation: 8,
              icon: const Icon(Icons.add, size: 24),
              label: const Text(
                'Add Custom Question',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
      bottomNavigationBar: widget.eventModel.id.isEmpty
          ? _buildContinueButton()
          : null,
    );
  }

  Widget _bodyView() {
    return Container(
      width: _screenWidth,
      height: _screenHeight,
      child: Column(
        children: [
          _headerView(),
          Expanded(child: _contentView()),
        ],
      ),
    );
  }

  Widget _headerView() {
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
                onTap: () {
                  // Simply pop back to the previous screen (AddQuestionsPromptScreen)
                  Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
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
              const Expanded(
                child: Text(
                  'Add Sign-In Prompts',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Create questions that attendees will answer when signing in',
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

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Templates Section
            _buildTemplatesSection(),
            const SizedBox(height: 24),
            // Current Questions Section
            _buildCurrentQuestionsSection(),
            // Add bottom padding for the continue button during event creation
            SizedBox(height: widget.eventModel.id.isEmpty ? 140 : 100),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Quick Templates',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showTemplates = !_showTemplates;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _showTemplates ? 'Hide' : 'Show',
                    style: const TextStyle(
                      color: Color(0xFF667EEA),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose from professional templates designed for real event needs',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
          if (_showTemplates) ...[
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio:
                    1.1, // Slightly taller to accommodate description
              ),
              itemCount: _questionTemplates.length,
              itemBuilder: (context, index) {
                final template = _questionTemplates[index];
                return _buildTemplateCard(template);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> template) {
    return GestureDetector(
      onTap: () => _addTemplateQuestion(template),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: template['color'].withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: template['color'].withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: template['color'],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(template['icon'], color: Colors.white, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              template['category'],
              style: TextStyle(
                color: template['color'],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template['title'],
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Roboto',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    template['description'] ?? '',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 10,
                      fontFamily: 'Roboto',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: template['color'],
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'Add',
                  style: TextStyle(
                    color: template['color'],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentQuestionsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.question_answer,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Current Questions',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              Text(
                '${questionsList.length} question${questionsList.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF667EEA)),
            )
          else if (questionsList.isEmpty)
            _buildEmptyState()
          else
            _buildQuestionsList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.question_mark,
              color: Color(0xFF667EEA),
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No questions yet',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add questions to collect information from attendees when they sign in',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: questionsList.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildQuestionCard(questionsList[index], index);
      },
    );
  }

  Widget _buildQuestionCard(EventQuestionModel question, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
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
                  question.questionTitle,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: question.required
                        ? const Color(0xFFEF4444).withOpacity(0.1)
                        : const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    question.required ? 'Required' : 'Optional',
                    style: TextStyle(
                      color: question.required
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF6B7280)),
            onSelected: (value) {
              if (value == 'delete') {
                _showDeleteConfirmation(question);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Color(0xFFEF4444)),
                    SizedBox(width: 8),
                    Text(
                      'Delete',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(EventQuestionModel question) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete Question',
            style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Roboto'),
          ),
          content: Text(
            'Are you sure you want to delete "${question.questionTitle}"? This action cannot be undone.',
            style: const TextStyle(fontFamily: 'Roboto'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontFamily: 'Roboto',
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteQuestion(question);
              },
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContinueButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add Custom Question Button
            Container(
              width: double.infinity,
              height: 56,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF667EEA), width: 2),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AddQuestionPopup(eventModel: widget.eventModel);
                      },
                    ).then((newQuestion) {
                      if (newQuestion != null) {
                        setState(() {
                          questionsList.add(newQuestion);
                        });
                      }
                    });
                  },
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add,
                          color: const Color(0xFF667EEA),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Add Custom Question',
                          style: TextStyle(
                            color: const Color(0xFF667EEA),
                            fontWeight: FontWeight.w600,
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
            // Continue to Event Creation Button
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withOpacity(0.3),
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
                  onTap: _continueToEventCreation,
                  child: Center(
                    child: Text(
                      'Continue to Event Creation',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _continueToEventCreation() {
    if (widget.eventCreationData != null) {
      // Navigate to CreateEventScreen with the questions
      RouterClass.nextScreenNormal(
        context,
        CreateEventScreen(
          selectedDateTime: widget.eventCreationData!['selectedDateTime'],
          selectedLocation: widget.eventCreationData!['selectedLocation'],
          radios: widget.eventCreationData!['radios'],
          selectedSignInMethods:
              widget.eventCreationData!['selectedSignInMethods'],
          manualCode: widget.eventCreationData!['manualCode'],
          questions: questionsList, // Pass the questions to CreateEventScreen
        ),
      );
    }
  }
}
