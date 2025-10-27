import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/Utils/cached_image.dart';

class EventCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final bool isAdmin;

  const EventCard({
    super.key,
    required this.data,
    required this.docId,
    required this.organizationId,
    this.isAdmin = false,
  });

  Future<bool> _checkIfAdmin() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    try {
      final orgDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];
      if (createdBy == currentUser.uid) return true;

      final memberDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(organizationId)
          .collection('Members')
          .doc(currentUser.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        return role == 'admin' || role == 'owner';
      }
    } catch (e) {
      debugPrint('Error checking admin status: $e');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isPinned = data['isPinned'] ?? false;
    final title = data['title'] ?? 'Untitled Event';
    final description = data['description'] ?? '';
    final eventDateTime =
        (data['selectedDateTime'] as Timestamp?)?.toDate() ??
        (data['eventDateTime'] as Timestamp?)?.toDate();
    final location = data['selectedLocation'] ?? data['location'] ?? '';
    final imageUrl = data['imageUrl'] ?? '';
    final creatorName = data['customerName'] ?? 'Unknown';

    Future<String> resolveCreatorName() async {
      final raw = creatorName.toString().trim();
      if (raw.isNotEmpty && raw.toLowerCase() != 'unknown') return raw;
      final String? creatorId = data['customerUid'] ?? data['authorId'];
      if (creatorId != null && creatorId.isNotEmpty) {
        final user = await FirebaseFirestoreHelper().getSingleCustomer(
          customerId: creatorId,
        );
        if (user != null) {
          final resolved = user.name.trim().isNotEmpty
              ? user.name
              : (user.username ?? '').trim();
          if (resolved.isNotEmpty) return resolved;
        }
      }
      return 'Unknown';
    }

    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPinned
              ? Border.all(color: const Color(0xFF667EEA), width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: () {
            // Navigate to event details
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SingleEventScreen(
                  eventModel: EventModel.fromJson({...data, 'id': docId}),
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pinned indicator
              if (isPinned)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF667EEA),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.push_pin, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'PINNED EVENT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Event image with elegant placeholder
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(isPinned ? 0 : 16),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: imageUrl.isNotEmpty
                      ? SafeNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF667EEA).withValues(alpha: 0.1),
                                const Color(0xFF764BA2).withValues(alpha: 0.1),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF667EEA)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                  child: Image.asset(
                                    'attendus_logo_only.png',
                                    width: 40,
                                    height: 40,
                                    errorBuilder: (context, error, stackTrace) {
                                      // Fallback to icon if logo not found
                                      return const Icon(
                                        Icons.event,
                                        color: Color(0xFF667EEA),
                                        size: 32,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Event badge and menu
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF667EEA,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'EVENT',
                            style: TextStyle(
                              color: Color(0xFF667EEA),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (isAdmin)
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              color: Colors.grey.shade600,
                              size: 20,
                            ),
                            onSelected: (value) async {
                              if (value == 'pin' || value == 'unpin') {
                                // Double-check admin status before allowing pin operation
                                final isAdminCheck = await _checkIfAdmin();
                                if (!isAdminCheck) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Only admins can pin/unpin content',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                try {
                                  await FirebaseFirestore.instance
                                      .collection('Events')
                                      .doc(docId)
                                      .update({'isPinned': value == 'pin'});

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          value == 'pin'
                                              ? 'Event pinned'
                                              : 'Event unpinned',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: isPinned ? 'unpin' : 'pin',
                                child: Row(
                                  children: [
                                    Icon(
                                      isPinned
                                          ? Icons.push_pin_outlined
                                          : Icons.push_pin,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(isPinned ? 'Unpin' : 'Pin'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Event title
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Event details
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          eventDateTime != null
                              ? DateFormat.MMMd().add_jm().format(eventDateTime)
                              : 'Date TBD',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),

                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Creator info
                    Row(
                      children: [
                        FutureBuilder<String>(
                          future: resolveCreatorName(),
                          builder: (context, snapshot) {
                            final displayName = (snapshot.data ?? creatorName)
                                .trim();
                            return Text(
                              'by ${displayName.isNotEmpty ? displayName : 'Unknown'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            );
                          },
                        ),
                      ],
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
}
