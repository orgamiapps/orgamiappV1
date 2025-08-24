import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/event_question_model.dart';
import 'package:orgami/screens/Events/Widget/add_question_popup.dart';
import 'package:orgami/screens/Events/create_event_screen.dart';
import 'package:orgami/Utils/router.dart';

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

  List<EventQuestionModel> questionsList = [];
  bool _isLoading = true;
  bool _showTemplates = false;
  final Set<String> _selectedTemplateTitles = <String>{};
  String _selectedTemplateCategory = 'All'; // New category filter
  final TextEditingController _searchController =
      TextEditingController(); // New search functionality

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Pre-built question templates - Professional questions that event hosts actually want to ask
  final List<Map<String, dynamic>> _questionTemplates = [
    // Marketing & Discovery
    {
      'title': 'How did you hear about this event?',
      'category': 'Marketing',
      'icon': Icons.campaign,
      'color': Color(0xFF667EEA),
      'description': 'Track marketing effectiveness and ROI',
    },
    {
      'title': 'Which social media platform led you here?',
      'category': 'Marketing',
      'icon': Icons.share,
      'color': Color(0xFF667EEA),
      'description': 'Identify top-performing channels',
    },

    // Attendee Experience & Engagement
    {
      'title': 'What is your primary reason for attending?',
      'category': 'Experience',
      'icon': Icons.psychology,
      'color': Color(0xFF10B981),
      'description': 'Understand attendee motivations',
    },
    {
      'title': 'What are you most excited to learn about today?',
      'category': 'Experience',
      'icon': Icons.lightbulb,
      'color': Color(0xFF10B981),
      'description': 'Tailor content to audience interests',
    },
    {
      'title': 'Is this your first time attending our events?',
      'category': 'Experience',
      'icon': Icons.history,
      'color': Color(0xFF10B981),
      'description': 'Customize experience for new vs returning attendees',
    },

    // Professional & Networking
    {
      'title': 'What industry or field do you work in?',
      'category': 'Professional',
      'icon': Icons.business,
      'color': Color(0xFF7C3AED),
      'description': 'Enable targeted networking opportunities',
    },
    {
      'title': 'What is your current role or job title?',
      'category': 'Professional',
      'icon': Icons.work,
      'color': Color(0xFF7C3AED),
      'description': 'Facilitate peer-to-peer connections',
    },
    {
      'title': 'How many years of experience do you have in your field?',
      'category': 'Professional',
      'icon': Icons.timeline,
      'color': Color(0xFF7C3AED),
      'description': 'Group participants by experience level',
    },

    // Logistics & Planning
    {
      'title': 'Do you have any dietary restrictions or food allergies?',
      'category': 'Logistics',
      'icon': Icons.restaurant_menu,
      'color': Color(0xFFFF9800),
      'description': 'Ensure safe and inclusive catering',
    },
    {
      'title': 'How many people are in your group today?',
      'category': 'Logistics',
      'icon': Icons.groups,
      'color': Color(0xFFFF9800),
      'description': 'Plan seating arrangements and materials',
    },
    {
      'title': 'Do you require any accessibility accommodations?',
      'category': 'Logistics',
      'icon': Icons.accessibility_new,
      'color': Color(0xFFFF9800),
      'description': 'Provide inclusive experience for all attendees',
    },
    {
      'title': 'Are you planning to stay for the entire event?',
      'category': 'Logistics',
      'icon': Icons.schedule,
      'color': Color(0xFFFF9800),
      'description': 'Manage capacity and resource allocation',
    },

    // Communication & Follow-up
    {
      'title': 'Would you like to receive updates about future events?',
      'category': 'Communication',
      'icon': Icons.email,
      'color': Color(0xFF8B5CF6),
      'description': 'Build your mailing list with permission',
    },
    {
      'title': 'How would you prefer to receive event updates?',
      'category': 'Communication',
      'icon': Icons.notifications_active,
      'color': Color(0xFF8B5CF6),
      'description': 'Optimize communication preferences',
    },

    // Feedback & Preferences
    {
      'title': 'What topics or sessions interest you most?',
      'category': 'Preferences',
      'icon': Icons.favorite,
      'color': Color(0xFFEF4444),
      'description': 'Personalize content recommendations',
    },
    {
      'title': 'What type of networking opportunities are you seeking?',
      'category': 'Preferences',
      'icon': Icons.people_alt,
      'color': Color(0xFFEF4444),
      'description': 'Facilitate meaningful connections',
    },
    {
      'title': 'Rate your current knowledge level on today\'s topics',
      'category': 'Preferences',
      'icon': Icons.star,
      'color': Color(0xFFEF4444),
      'description': 'Match content complexity to audience level',
    },

    // Demographics & Analytics
    {
      'title': 'What is your age range?',
      'category': 'Demographics',
      'icon': Icons.cake,
      'color': Color(0xFF06B6D4),
      'description': 'Understand audience demographics',
    },
    {
      'title': 'Which city or region are you from?',
      'category': 'Demographics',
      'icon': Icons.location_city,
      'color': Color(0xFF06B6D4),
      'description': 'Track geographical reach',
    },

    // Event-Specific Contexts
    {
      'title': 'Are you attending as part of a company or organization?',
      'category': 'Context',
      'icon': Icons.corporate_fare,
      'color': Color(0xFF059669),
      'description': 'Identify corporate vs individual attendees',
    },
    {
      'title': 'What are your main goals for today\'s event?',
      'category': 'Context',
      'icon': Icons.flag,
      'color': Color(0xFF059669),
      'description': 'Align event delivery with attendee objectives',
    },
    {
      'title': 'How did you first learn about our organization?',
      'category': 'Context',
      'icon': Icons.explore,
      'color': Color(0xFF059669),
      'description': 'Track brand awareness and discovery paths',
    },

    // Health & Safety (Post-pandemic considerations)
    {
      'title': 'Do you have any health considerations we should be aware of?',
      'category': 'Safety',
      'icon': Icons.health_and_safety,
      'color': Color(0xFFDC2626),
      'description': 'Ensure safe event environment',
    },

    // Technology & Digital
    {
      'title': 'Would you like to connect on our event app or platform?',
      'category': 'Technology',
      'icon': Icons.smartphone,
      'color': Color(0xFF7E22CE),
      'description': 'Drive digital engagement and app adoption',
    },
  ];

  // Get unique categories for filtering
  List<String> get _templateCategories {
    final categories = _questionTemplates
        .map((template) => template['category'] as String)
        .toSet()
        .toList();
    categories.sort();
    categories.insert(0, 'All');
    return categories;
  }

  // Filter templates based on category and search
  List<Map<String, dynamic>> get _filteredTemplates {
    List<Map<String, dynamic>> filtered = _questionTemplates;

    // Filter by category
    if (_selectedTemplateCategory != 'All') {
      filtered = filtered
          .where(
            (template) => template['category'] == _selectedTemplateCategory,
          )
          .toList();
    }

    // Filter by search term
    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      filtered = filtered.where((template) {
        final title = (template['title'] as String).toLowerCase();
        final description = (template['description'] as String).toLowerCase();
        final category = (template['category'] as String).toLowerCase();
        return title.contains(searchTerm) ||
            description.contains(searchTerm) ||
            category.contains(searchTerm);
      }).toList();
    }

    return filtered;
  }

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

      if (mounted) {
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
      }
    } catch (e) {
      if (mounted) {
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
  }

  Future<void> _addTemplateQuestion(Map<String, dynamic> template) async {
    // Check for duplicates first
    final questionTitle = template['title'] as String;
    final isDuplicate = questionsList.any(
      (question) =>
          question.questionTitle.toLowerCase().trim() ==
          questionTitle.toLowerCase().trim(),
    );

    if (isDuplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question "${template['title']}" already exists'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

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

      if (mounted) {
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
      }
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Question "${template['title']}" added successfully',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
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

    // Start with templates collapsed to reduce initial overwhelm
    // Users can expand when they want to browse all templates.
    _showTemplates = false;

    _getQuestions();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _searchController.dispose();
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
    return SizedBox(
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
          // Header with toggle
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Professional Question Templates',
                      style: TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pre-built questions for real event scenarios',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showTemplates = !_showTemplates;
                    if (!_showTemplates) {
                      // Reset filters when hiding templates
                      _selectedTemplateCategory = 'All';
                      _searchController.clear();
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _showTemplates
                        ? const Color(0xFF667EEA).withOpacity(0.1)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showTemplates ? Icons.expand_less : Icons.expand_more,
                        color: _showTemplates
                            ? const Color(0xFF667EEA)
                            : const Color(0xFF6B7280),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showTemplates ? 'Hide' : 'Show',
                        style: TextStyle(
                          color: _showTemplates
                              ? const Color(0xFF667EEA)
                              : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_showTemplates) ...[
            const SizedBox(height: 20),

            // Search and category filters
            Row(
              children: [
                // Search field
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search templates...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF6B7280),
                        size: 20,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Color(0xFF6B7280),
                                size: 18,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE5E7EB),
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE5E7EB),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF667EEA),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(fontSize: 14, fontFamily: 'Roboto'),
                  ),
                ),
                const SizedBox(width: 12),

                // Category dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTemplateCategory,
                        isExpanded: true,
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'Roboto',
                          color: Color(0xFF1A1A1A),
                        ),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Color(0xFF6B7280),
                        ),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedTemplateCategory = newValue!;
                          });
                        },
                        items: _templateCategories
                            .map<DropdownMenuItem<String>>((String category) {
                              return DropdownMenuItem<String>(
                                value: category,
                                child: Text(
                                  category,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Results count and selected count
            if (_filteredTemplates.isNotEmpty) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_filteredTemplates.length} template${_filteredTemplates.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                  if (_selectedTemplateCategory != 'All') ...[
                    const SizedBox(width: 8),
                    Text(
                      'in $_selectedTemplateCategory',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Templates grid or empty state
            if (_filteredTemplates.isEmpty)
              _buildEmptyTemplatesState()
            else
              MasonryGridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                itemCount: _filteredTemplates.length,
                itemBuilder: (context, index) {
                  final template = _filteredTemplates[index];
                  return _buildTemplateCard(template);
                },
              ),

            if (_showTemplates && _selectedTemplateTitles.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildAddSelectedBar(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyTemplatesState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF6B7280).withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(
              Icons.search_off,
              color: Color(0xFF6B7280),
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No templates found',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchController.text.isNotEmpty
                ? 'Try different search terms or change category'
                : 'Try selecting a different category',
            style: const TextStyle(
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

  Widget _buildTemplateCard(Map<String, dynamic> template) {
    final questionTitle = template['title'] as String;
    final isAlreadyAdded = questionsList.any(
      (question) =>
          question.questionTitle.toLowerCase().trim() ==
          questionTitle.toLowerCase().trim(),
    );
    final bool isSelected = _selectedTemplateTitles.contains(questionTitle);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isAlreadyAdded) return;
          setState(() {
            if (isSelected) {
              _selectedTemplateTitles.remove(questionTitle);
            } else {
              _selectedTemplateTitles.add(questionTitle);
            }
          });
        },
        onLongPress: () => _showTemplatePreview(template),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isAlreadyAdded
                ? const Color(0xFFF3F4F6)
                : (isSelected
                      ? template['color'].withOpacity(0.18)
                      : template['color'].withOpacity(0.08)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAlreadyAdded
                  ? const Color(0xFFE5E7EB)
                  : (isSelected
                        ? template['color']
                        : template['color'].withOpacity(0.2)),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category tag and icon
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isAlreadyAdded
                          ? const Color(0xFF6B7280)
                          : template['color'],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isAlreadyAdded
                          ? Icons.check
                          : (isSelected ? Icons.check : template['icon']),
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isAlreadyAdded
                            ? const Color(0xFFF3F4F6)
                            : template['color'].withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isAlreadyAdded
                            ? 'Added'
                            : (isSelected ? 'Selected' : template['category']),
                        style: TextStyle(
                          color: isAlreadyAdded
                              ? const Color(0xFF6B7280)
                              : template['color'],
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Roboto',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Question title
              Text(
                template['title'],
                style: TextStyle(
                  color: isAlreadyAdded
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF1A1A1A),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                  height: 1.35,
                  decoration: isAlreadyAdded
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                template['description'] ?? '',
                style: TextStyle(
                  color: isAlreadyAdded
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                  fontSize: 9,
                  fontFamily: 'Roboto',
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),

              // Selection hint bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isAlreadyAdded
                      ? const Color(0xFFF3F4F6)
                      : (isSelected
                            ? template['color'].withOpacity(0.18)
                            : template['color'].withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isAlreadyAdded
                          ? Icons.check_circle
                          : (isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked),
                      color: isAlreadyAdded
                          ? const Color(0xFF6B7280)
                          : template['color'],
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isAlreadyAdded
                          ? 'Already Added'
                          : (isSelected ? 'Selected' : 'Tap to Select'),
                      style: TextStyle(
                        color: isAlreadyAdded
                            ? const Color(0xFF6B7280)
                            : template['color'],
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddSelectedBar() {
    final Color accent = const Color(0xFF667EEA);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selectedTemplateTitles.length} selected',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _selectedTemplateTitles.clear());
            },
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _handleAddSelected,
            label: const Text('Add Selected'),
          ),
        ],
      ),
    );
  }

  void _handleAddSelected() {
    if (_selectedTemplateTitles.isEmpty) return;
    final List<Map<String, dynamic>> selectedTemplates = _filteredTemplates
        .where((t) => _selectedTemplateTitles.contains(t['title'] as String))
        .toList();

    for (final template in selectedTemplates) {
      _addTemplateQuestion(template);
    }
    setState(() => _selectedTemplateTitles.clear());
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

  void _showTemplatePreview(Map<String, dynamic> template) {
    final String title = template['title'] as String;
    final String? description = template['description'] as String?;
    final Color accent =
        (template['color'] as Color?) ?? const Color(0xFF667EEA);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final bool isAlreadyAdded = questionsList.any(
          (q) =>
              q.questionTitle.toLowerCase().trim() ==
              title.toLowerCase().trim(),
        );

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.06),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                          fontFamily: 'Roboto',
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (description != null && description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4B5563),
                      fontFamily: 'Roboto',
                      height: 1.4,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: accent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAlreadyAdded
                              ? const Color(0xFFF3F4F6)
                              : accent,
                          foregroundColor: isAlreadyAdded
                              ? const Color(0xFF6B7280)
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: isAlreadyAdded
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                _addTemplateQuestion(template);
                              },
                        child: Text(
                          isAlreadyAdded ? 'Already Added' : 'Add Question',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          eventDurationHours: widget.eventCreationData!['eventDurationHours'],
          selectedLocation: widget.eventCreationData!['selectedLocation'],
          radios: widget.eventCreationData!['radios'],
          selectedSignInMethods:
              widget.eventCreationData!['selectedSignInMethods'],
          manualCode: widget.eventCreationData!['manualCode'],
          questions: questionsList,
          preselectedOrganizationId:
              widget.eventCreationData!['preselectedOrganizationId'],
          forceOrganizationEvent:
              widget.eventCreationData!['forceOrganizationEvent'] == true,
        ),
      );
    }
  }
}
