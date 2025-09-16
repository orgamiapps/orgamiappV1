import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreatePollScreen extends StatefulWidget {
  final String organizationId;
  const CreatePollScreen({super.key, required this.organizationId});

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final _formKey = GlobalKey<FormState>();
  bool _isPosting = false;
  bool _allowMultipleVotes = false;
  DateTime? _endDate;
  bool _isAdmin = false;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkAdminPermission();
  }

  Future<void> _checkAdminPermission() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _checkingPermission = false);
      return;
    }

    try {
      // Check if user is admin or creator
      final orgDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];

      // Check if user is creator
      if (createdBy == user.uid) {
        setState(() {
          _isAdmin = true;
          _checkingPermission = false;
        });
        return;
      }

      // Check if user is admin in Members collection
      final memberDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        setState(() {
          _isAdmin = role == 'admin' || role == 'owner';
          _checkingPermission = false;
        });
      } else {
        setState(() => _checkingPermission = false);
      }
    } catch (e) {
      setState(() => _checkingPermission = false);
    }
  }

  void _addOption() {
    if (_optionControllers.length < 6) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (time != null) {
        setState(() {
          _endDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _createPoll() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isPosting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Get non-empty options
      final options = _optionControllers
          .map((controller) => controller.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      if (options.length < 2) {
        throw Exception('At least 2 options are required');
      }

      // Create poll options with initial vote counts
      final pollOptions = <Map<String, dynamic>>[];
      for (String option in options) {
        pollOptions.add({'text': option, 'votes': [], 'voteCount': 0});
      }

      // Create poll document
      await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .add({
            'type': 'poll',
            'question': _questionController.text.trim(),
            'options': pollOptions,
            'authorId': user.uid,
            'authorName': user.displayName ?? 'Unknown',
            'authorEmail': user.email,
            'createdAt': FieldValue.serverTimestamp(),
            'endDate': _endDate != null ? Timestamp.fromDate(_endDate!) : null,
            'allowMultipleVotes': _allowMultipleVotes,
            'totalVotes': 0,
            'voters': [],
            'isActive': true,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Poll created successfully!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating poll: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Create Poll'),
          backgroundColor: const Color(0xFF667EEA),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Create Poll'),
          backgroundColor: const Color(0xFF667EEA),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Admin Access Required',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Only group admins can create polls',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Poll'),
        backgroundColor: const Color(0xFF667EEA),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _createPoll,
            child: _isPosting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Create',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _questionController,
              decoration: InputDecoration(
                labelText: 'Poll Question',
                hintText: 'What would you like to ask?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.help_outline),
              ),
              maxLength: 200,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a question';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.list, color: Color(0xFF667EEA)),
                const SizedBox(width: 8),
                const Text(
                  'Poll Options',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_optionControllers.length < 6)
                  TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Option'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ..._optionControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: 'Option ${index + 1}',
                          hintText: 'Enter option ${index + 1}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: CircleAvatar(
                            radius: 12,
                            backgroundColor: const Color(0xFF667EEA),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (index < 2 &&
                              (value == null || value.trim().isEmpty)) {
                            return 'This option is required';
                          }
                          return null;
                        },
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _removeOption(index),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Allow multiple votes'),
                    subtitle: const Text('Users can vote for multiple options'),
                    value: _allowMultipleVotes,
                    onChanged: (value) {
                      setState(() => _allowMultipleVotes = value);
                    },
                    activeThumbColor: const Color(0xFF667EEA),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('End date (optional)'),
                    subtitle: Text(
                      _endDate != null
                          ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year} at ${_endDate!.hour.toString().padLeft(2, '0')}:${_endDate!.minute.toString().padLeft(2, '0')}'
                          : 'No end date set',
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        _endDate != null
                            ? Icons.edit_calendar
                            : Icons.calendar_today,
                        color: const Color(0xFF667EEA),
                      ),
                      onPressed: _selectEndDate,
                    ),
                    onTap: _selectEndDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This poll will be visible to all group members. They can vote directly from the Feed tab.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
