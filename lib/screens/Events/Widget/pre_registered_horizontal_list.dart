import 'package:flutter/material.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/attendance_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/ticket_model.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:orgami/Screens/MyProfile/user_profile_screen.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PreRegisteredHorizontalList extends StatefulWidget {
  final EventModel eventModel;

  const PreRegisteredHorizontalList({super.key, required this.eventModel});

  @override
  State<PreRegisteredHorizontalList> createState() =>
      _PreRegisteredHorizontalListState();
}

class _PreRegisteredHorizontalListState
    extends State<PreRegisteredHorizontalList> {
  // Local caches (optional)
  List<AttendanceModel> preRegistered = [];
  List<TicketModel> eventTickets = [];
  List<CustomerModel> customerDetails = [];
  bool isLoading = true;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadRegisteredAndTicketedUsers();
  }

  Future<void> _loadRegisteredAndTicketedUsers() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Get all pre-registered for this event
      final preRegisteredList = await FirebaseFirestoreHelper()
          .getRegisterAttendance(eventId: widget.eventModel.id);

      // Get all tickets for this event
      final ticketsList = await FirebaseFirestoreHelper().getEventTickets(
        eventId: widget.eventModel.id,
      );

      // Combine unique users (both registered and ticketed)
      final Set<String> uniqueUserIds = <String>{};
      final List<AttendanceModel> allUsers = [];

      // Add registered users
      for (var attendee in preRegisteredList) {
        if (!uniqueUserIds.contains(attendee.customerUid)) {
          uniqueUserIds.add(attendee.customerUid);
          allUsers.add(attendee);
        }
      }

      // Add users with tickets who aren't already in the registered list
      for (var ticket in ticketsList) {
        if (!uniqueUserIds.contains(ticket.customerUid)) {
          uniqueUserIds.add(ticket.customerUid);
          // Create a registration record for ticket holders
          allUsers.add(
            AttendanceModel(
              id: 'ticket_${ticket.id}',
              eventId: ticket.eventId,
              userName: ticket.customerName,
              customerUid: ticket.customerUid,
              attendanceDateTime: ticket.issuedDateTime,
              answers: [],
              isAnonymous: false,
              realName: ticket.customerName,
            ),
          );
        }
      }

      // Get customer details for each user (limit to first 10 for performance)
      List<CustomerModel> customers = [];
      for (var attendee in allUsers.take(10)) {
        final customer = await FirebaseFirestoreHelper().getSingleCustomer(
          customerId: attendee.customerUid,
        );
        if (customer != null) {
          customers.add(customer);
        }
      }

      setState(() {
        preRegistered = allUsers;
        eventTickets = ticketsList;
        customerDetails = customers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      Logger.error('Error loading registered and ticketed users: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Real-time stream of RSVPs
    final rsvpStream = FirebaseFirestore.instance
        .collection(AttendanceModel.registerFirebaseKey)
        .where('eventId', isEqualTo: widget.eventModel.id)
        .snapshots();

    // Tickets stream
    final ticketsStream = FirebaseFirestoreHelper().getTicketsStream(
      widget.eventModel.id,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: StreamBuilder<QuerySnapshot>(
        stream: rsvpStream,
        builder: (context, rsvpSnapshot) {
          if (rsvpSnapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 100,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppThemeColor.darkGreenColor,
                  strokeWidth: 2,
                ),
              ),
            );
          }

          final preRegDocs = rsvpSnapshot.data?.docs ?? [];
          final preRegModels = preRegDocs
              .map((d) => AttendanceModel.fromJson(d))
              .toList();

          return StreamBuilder<List<TicketModel>>(
            stream: ticketsStream,
            builder: (context, ticketsSnapshot) {
              final tickets = ticketsSnapshot.data ?? [];

              // Merge unique RSVPs + ticket holders
              final Set<String> uniqueUserIds = <String>{};
              final List<AttendanceModel> allUsers = [];

              for (var attendee in preRegModels) {
                if (!uniqueUserIds.contains(attendee.customerUid)) {
                  uniqueUserIds.add(attendee.customerUid);
                  allUsers.add(attendee);
                }
              }
              for (var ticket in tickets) {
                if (!uniqueUserIds.contains(ticket.customerUid)) {
                  uniqueUserIds.add(ticket.customerUid);
                  allUsers.add(
                    AttendanceModel(
                      id: 'ticket_${ticket.id}',
                      eventId: ticket.eventId,
                      userName: ticket.customerName,
                      customerUid: ticket.customerUid,
                      attendanceDateTime: ticket.issuedDateTime,
                      answers: [],
                      isAnonymous: false,
                      realName: ticket.customerName,
                    ),
                  );
                }
              }

              // Use cached customers if available (fallback to showing names)
              final customers = customerDetails;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with dropdown toggle and count
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          spreadRadius: 0,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF667EEA,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.how_to_reg,
                              color: Color(0xFF667EEA),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "RSVP's (${allUsers.length})",
                                  style: const TextStyle(
                                    color: Color(0xFF1A1A1A),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                Text(
                                  allUsers.isEmpty
                                      ? "No RSVP's yet"
                                      : "Tap to see RSVP's",
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 14,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedRotation(
                            turns: _isExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF667EEA),
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Collapsible content
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: _isExpanded ? null : 0,
                    child: !_isExpanded
                        ? const SizedBox.shrink()
                        : (allUsers.isEmpty
                              ? Center(
                                  child: Text(
                                    "No RSVP's yet",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 14,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                )
                              : Column(
                                  children: [
                                    // See All button (expanded only)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          GestureDetector(
                                            onTap: () => _showAllRsvpsPopup(
                                              allUsers,
                                              customers,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF667EEA,
                                                ).withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFF667EEA,
                                                  ),
                                                  width: 1,
                                                ),
                                              ),
                                              child: const Text(
                                                'See All',
                                                style: TextStyle(
                                                  color: Color(0xFF667EEA),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'Roboto',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Horizontal list
                                    SizedBox(
                                      height: 100,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                        ),
                                        itemCount: allUsers.length > 5
                                            ? 5
                                            : allUsers.length,
                                        itemBuilder: (context, index) {
                                          final attendee = allUsers[index];
                                          final customer = customers.firstWhere(
                                            (c) =>
                                                c.uid == attendee.customerUid,
                                            orElse: () => CustomerModel(
                                              uid: attendee.customerUid,
                                              name: attendee.userName,
                                              email: '',
                                              createdAt: DateTime.now(),
                                            ),
                                          );
                                          final isAnon = attendee.isAnonymous;

                                          return GestureDetector(
                                            onTap: () {
                                              if (!isAnon &&
                                                  customer.uid.isNotEmpty) {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        UserProfileScreen(
                                                          user: customer,
                                                          isOwnProfile:
                                                              CustomerController
                                                                  .logeInCustomer
                                                                  ?.uid ==
                                                              customer.uid,
                                                        ),
                                                  ),
                                                );
                                              }
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                right: 16,
                                              ),
                                              child: Column(
                                                children: [
                                                  // Modern Profile Picture
                                                  Container(
                                                    width: 56,
                                                    height: 56,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      gradient: isAnon
                                                          ? const LinearGradient(
                                                              begin: Alignment
                                                                  .topLeft,
                                                              end: Alignment
                                                                  .bottomRight,
                                                              colors: [
                                                                Color(
                                                                  0xFF6B7280,
                                                                ),
                                                                Color(
                                                                  0xFF9CA3AF,
                                                                ),
                                                              ],
                                                            )
                                                          : (attendee.id
                                                                    .startsWith(
                                                                      'ticket_',
                                                                    )
                                                                ? const LinearGradient(
                                                                    begin: Alignment
                                                                        .topLeft,
                                                                    end: Alignment
                                                                        .bottomRight,
                                                                    colors: [
                                                                      Color(
                                                                        0xFFFF9800,
                                                                      ),
                                                                      Color(
                                                                        0xFFFF5722,
                                                                      ),
                                                                    ],
                                                                  )
                                                                : const LinearGradient(
                                                                    begin: Alignment
                                                                        .topLeft,
                                                                    end: Alignment
                                                                        .bottomRight,
                                                                    colors: [
                                                                      Color(
                                                                        0xFF667EEA,
                                                                      ),
                                                                      Color(
                                                                        0xFF764BA2,
                                                                      ),
                                                                    ],
                                                                  )),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: isAnon
                                                              ? const Color(
                                                                  0xFF6B7280,
                                                                ).withValues(
                                                                  alpha: 0.3,
                                                                )
                                                              : (attendee.id.startsWith(
                                                                      'ticket_',
                                                                    )
                                                                    ? const Color(
                                                                        0xFFFF9800,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      )
                                                                    : const Color(
                                                                        0xFF667EEA,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      )),
                                                          spreadRadius: 0,
                                                          blurRadius: 8,
                                                          offset: const Offset(
                                                            0,
                                                            4,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: ClipOval(
                                                      child: isAnon
                                                          ? Container(
                                                              color: Colors
                                                                  .transparent,
                                                              child: const Icon(
                                                                Icons
                                                                    .person_off,
                                                                size: 28,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            )
                                                          : (customer.profilePictureUrl !=
                                                                    null
                                                                ? Image.network(
                                                                    customer
                                                                        .profilePictureUrl!,
                                                                    fit: BoxFit
                                                                        .cover,
                                                                    errorBuilder:
                                                                        (
                                                                          context,
                                                                          error,
                                                                          stackTrace,
                                                                        ) {
                                                                          return Container(
                                                                            color:
                                                                                Colors.transparent,
                                                                            child: const Icon(
                                                                              Icons.person,
                                                                              size: 28,
                                                                              color: Colors.white,
                                                                            ),
                                                                          );
                                                                        },
                                                                  )
                                                                : Container(
                                                                    color: Colors
                                                                        .transparent,
                                                                    child: const Icon(
                                                                      Icons
                                                                          .person,
                                                                      size: 28,
                                                                      color: Colors
                                                                          .white,
                                                                    ),
                                                                  )),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // Name with better styling
                                                  SizedBox(
                                                    width: 70,
                                                    child: Text(
                                                      isAnon
                                                          ? 'Anonymous'
                                                          : (attendee.customerUid ==
                                                                    'without_login'
                                                                ? attendee
                                                                      .userName
                                                                : customer
                                                                      .name),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: isAnon
                                                            ? const Color(
                                                                0xFF6B7280,
                                                              )
                                                            : const Color(
                                                                0xFF1A1A1A,
                                                              ),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontFamily: 'Roboto',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                )),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showAllRsvpsPopup(
    List<AttendanceModel> list,
    List<CustomerModel> customers,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.how_to_reg,
                        color: Color(0xFF667EEA),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "All RSVP's & Ticketed",
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          Text(
                            "${list.length} RSVP's & Ticketed",
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 14,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final attendee = list[index];
                      final customer = customers.firstWhere(
                        (c) => c.uid == attendee.customerUid,
                        orElse: () => CustomerModel(
                          uid: attendee.customerUid,
                          name: attendee.userName,
                          email: '',
                          createdAt: DateTime.now(),
                        ),
                      );
                      final isAnon = attendee.isAnonymous;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isAnon
                                    ? const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF6B7280),
                                          Color(0xFF9CA3AF),
                                        ],
                                      )
                                    : (attendee.id.startsWith('ticket_')
                                          ? const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFFFF9800),
                                                Color(0xFFFF5722),
                                              ],
                                            )
                                          : const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFF667EEA),
                                                Color(0xFF764BA2),
                                              ],
                                            )),
                                boxShadow: [
                                  BoxShadow(
                                    color: isAnon
                                        ? const Color(
                                            0xFF6B7280,
                                          ).withValues(alpha: 0.3)
                                        : (attendee.id.startsWith('ticket_')
                                              ? const Color(
                                                  0xFFFF9800,
                                                ).withValues(alpha: 0.3)
                                              : const Color(
                                                  0xFF667EEA,
                                                ).withValues(alpha: 0.3)),
                                    spreadRadius: 0,
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: isAnon
                                    ? Container(
                                        color: Colors.transparent,
                                        child: const Icon(
                                          Icons.person_off,
                                          size: 24,
                                          color: Colors.white,
                                        ),
                                      )
                                    : (customer.profilePictureUrl != null
                                          ? Image.network(
                                              customer.profilePictureUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return Container(
                                                      color: Colors.transparent,
                                                      child: const Icon(
                                                        Icons.person,
                                                        size: 24,
                                                        color: Colors.white,
                                                      ),
                                                    );
                                                  },
                                            )
                                          : Container(
                                              color: Colors.transparent,
                                              child: const Icon(
                                                Icons.person,
                                                size: 24,
                                                color: Colors.white,
                                              ),
                                            )),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Name and details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAnon
                                        ? 'Anonymous'
                                        : (attendee.customerUid ==
                                                  'without_login'
                                              ? attendee.userName
                                              : customer.name),
                                    style: TextStyle(
                                      color: isAnon
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFF1A1A1A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Status indicator
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: attendee.id.startsWith('ticket_')
                                    ? const Color(
                                        0xFFFF9800,
                                      ).withValues(alpha: 0.1)
                                    : const Color(
                                        0xFF667EEA,
                                      ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                attendee.id.startsWith('ticket_')
                                    ? 'Ticketed'
                                    : "RSVP'd",
                                style: TextStyle(
                                  color: attendee.id.startsWith('ticket_')
                                      ? const Color(0xFFFF9800)
                                      : const Color(0xFF667EEA),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
