import 'package:flutter/material.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/AllAttendeesScreen.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';

class AttendeesHorizontalList extends StatefulWidget {
  final EventModel eventModel;

  const AttendeesHorizontalList({super.key, required this.eventModel});

  @override
  State<AttendeesHorizontalList> createState() =>
      _AttendeesHorizontalListState();
}

class _AttendeesHorizontalListState extends State<AttendeesHorizontalList> {
  List<AttendanceModel> attendees = [];
  List<CustomerModel> customerDetails = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttendees();
  }

  Future<void> _loadAttendees() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Get all attendees for this event
      final attendeesList = await FirebaseFirestoreHelper().getAttendance(
        eventId: widget.eventModel.id,
      );

      print('DEBUG: Attendees fetched from Firestore:');
      for (var attendee in attendeesList) {
        print(
          '  - id: ${attendee.id}, userName: ${attendee.userName}, customerUid: ${attendee.customerUid}, isAnonymous: ${attendee.isAnonymous}',
        );
      }

      // Get customer details only for non-anonymous attendees (limit to first 10 for performance)
      List<CustomerModel> customers = [];
      int fetchedCount = 0;
      for (var attendee in attendeesList) {
        if (!attendee.isAnonymous && fetchedCount < 10) {
          final customer = await FirebaseFirestoreHelper().getSingleCustomer(
            customerId: attendee.customerUid,
          );
          if (customer != null) {
            customers.add(customer);
          }
          fetchedCount++;
        }
      }

      setState(() {
        attendees = attendeesList;
        customerDetails = customers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error loading attendees: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
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

    if (attendees.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modern Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  spreadRadius: 0,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.people,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attendees',
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      Text(
                        '${attendees.length} people signed in',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
                if (attendees.length > 5)
                  GestureDetector(
                    onTap: () {
                      RouterClass.nextScreenNormal(
                        context,
                        AllAttendeesScreen(eventModel: widget.eventModel),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'View All',
                        style: TextStyle(
                          color: Color(0xFF10B981),
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
          const SizedBox(height: 12),
          // Modern Attendees List
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: attendees.length > 5 ? 5 : attendees.length,
              itemBuilder: (context, index) {
                final attendee = attendees[index];
                final isAnon = attendee.isAnonymous;

                // Find customer only if not anonymous
                CustomerModel? customer;
                if (!isAnon) {
                  customer = customerDetails.firstWhere(
                    (c) => c.uid == attendee.customerUid,
                    orElse: () => CustomerModel(
                      uid: attendee.customerUid,
                      name: attendee.userName,
                      email: '',
                      createdAt: DateTime.now(),
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.only(right: 16),
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
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF6B7280),
                                    Color(0xFF9CA3AF),
                                  ],
                                )
                              : const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF10B981),
                                    Color(0xFF059669),
                                  ],
                                ),
                          boxShadow: [
                            BoxShadow(
                              color: isAnon
                                  ? const Color(0xFF6B7280).withOpacity(0.3)
                                  : const Color(0xFF10B981).withOpacity(0.3),
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
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                )
                              : (customer?.profilePictureUrl != null
                                    ? Image.network(
                                        customer!.profilePictureUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.transparent,
                                                child: const Icon(
                                                  Icons.person,
                                                  size: 28,
                                                  color: Colors.white,
                                                ),
                                              );
                                            },
                                      )
                                    : Container(
                                        color: Colors.transparent,
                                        child: const Icon(
                                          Icons.person,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                      )),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Name with better styling
                      SizedBox(
                        width: 70,
                        child: Text(
                          attendee.userName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isAnon
                                ? const Color(0xFF6B7280)
                                : const Color(0xFF1A1A1A),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
    );
  }
}
