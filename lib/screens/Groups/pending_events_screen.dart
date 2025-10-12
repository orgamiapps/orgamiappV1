import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';

class PendingEventsScreen extends StatefulWidget {
  final String organizationId;

  const PendingEventsScreen({super.key, required this.organizationId});

  @override
  State<PendingEventsScreen> createState() => _PendingEventsScreenState();
}

class _PendingEventsScreenState extends State<PendingEventsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final List<String> _processingEvents = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pending Events',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: FutureBuilder<bool>(
        future: _checkIfApprovalEnabled(),
        builder: (context, approvalSnapshot) {
          if (approvalSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final approvalEnabled = approvalSnapshot.data ?? false;

          if (!approvalEnabled) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Event Approval Disabled',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Event approval is currently disabled for this group. Member events go live immediately.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.settings),
                      label: const Text('Go to Event Settings'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _getPendingEventsStream(),
            builder: (context, snapshot) {
              // Debug: Print error details
              if (snapshot.hasError) {
                if (kDebugMode) {
                  debugPrint('Pending events query error: ${snapshot.error}');
                  debugPrint('Organization ID: ${widget.organizationId}');
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 64,
                          color: Colors.orange.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Connection Issue',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Having trouble connecting to the server. Please try again.',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF667EEA),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Handle both no data and empty results as "no pending events"
              if (!snapshot.hasData ||
                  snapshot.data == null ||
                  snapshot.data!.docs.isEmpty) {
                return _buildEmptyState();
              }

              final events = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final data = event.data() as Map<String, dynamic>;
                  return _buildEventCard(event.id, data);
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _checkIfApprovalEnabled() async {
    try {
      final doc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        return data['requireEventApproval'] ?? false;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking approval settings: $e');
      }
      return false;
    }
  }

  Stream<QuerySnapshot> _getPendingEventsStream() {
    try {
      return _db
          .collection('Events')
          .where('organizationId', isEqualTo: widget.organizationId)
          .where('status', isEqualTo: 'pending_approval')
          .snapshots();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error creating pending events stream: $e');
      }
      // Return empty stream in case of error
      return const Stream.empty();
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 64,
                color: const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All caught up!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No events are waiting for approval right now.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade600,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'When members create events that need approval, they\'ll appear here for you to review.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
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

  Widget _buildEventCard(String eventId, Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? 'Untitled Event';
    final description = data['description']?.toString() ?? '';
    final location = data['location']?.toString() ?? '';
    final creatorUid = data['customerUid']?.toString() ?? '';
    final createdAt = (data['eventGenerateTime'] as Timestamp?)?.toDate();
    final selectedDateTime = (data['selectedDateTime'] as Timestamp?)?.toDate();
    final isProcessing = _processingEvents.contains(eventId);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _previewEvent(eventId, data),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status and actions
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          size: 16,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Pending Approval',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (isProcessing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _approveEvent(eventId, data),
                          icon: const Icon(
                            Icons.check_circle,
                            color: Color(0xFF667EEA),
                          ),
                          tooltip: 'Approve Event',
                        ),
                        IconButton(
                          onPressed: () => _rejectEvent(eventId, data),
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          tooltip: 'Reject Event',
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Event details
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              if (selectedDateTime != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d, y • h:mm a').format(selectedDateTime),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],

              if (location.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.place, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Creator info
              FutureBuilder<CustomerModel?>(
                future: _getCreatorInfo(creatorUid),
                builder: (context, snapshot) {
                  final creator = snapshot.data;
                  final creatorName = creator?.name ?? 'Unknown User';

                  return Row(
                    children: [
                      GestureDetector(
                        onTap: creator != null
                            ? () => _viewCreatorProfile(creator)
                            : null,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(
                                0xFF667EEA,
                              ).withValues(alpha: 0.1),
                              child: Text(
                                creatorName.isNotEmpty
                                    ? creatorName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Color(0xFF667EEA),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Created by $creatorName',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                                if (createdAt != null)
                                  Text(
                                    _getTimeAgo(createdAt),
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _previewEvent(eventId, data),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('Preview'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF667EEA),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<CustomerModel?> _getCreatorInfo(String creatorUid) async {
    try {
      return await FirebaseFirestoreHelper().getSingleCustomer(
        customerId: creatorUid,
      );
    } catch (e) {
      return null;
    }
  }

  void _viewCreatorProfile(CustomerModel creator) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(user: creator, isOwnProfile: false),
      ),
    );
  }

  void _previewEvent(String eventId, Map<String, dynamic> data) {
    try {
      final model = EventModel.fromJson({...data, 'id': eventId});
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SingleEventScreen(eventModel: model)),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to preview event: $e')));
    }
  }

  Future<void> _approveEvent(String eventId, Map<String, dynamic> data) async {
    setState(() => _processingEvents.add(eventId));

    try {
      await _db.collection('Events').doc(eventId).update({
        'status': 'scheduled',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event "${data['title']}" approved successfully'),
            backgroundColor: const Color(0xFF667EEA),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _processingEvents.remove(eventId));
    }
  }

  Future<void> _rejectEvent(String eventId, Map<String, dynamic> data) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Event'),
        content: Text(
          'Are you sure you want to reject "${data['title']}"? This will permanently delete the event.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingEvents.add(eventId));

    try {
      // Delete the event instead of just changing status
      await _db.collection('Events').doc(eventId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event "${data['title']}" rejected and removed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _processingEvents.remove(eventId));
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat.yMMMd().format(dateTime);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
