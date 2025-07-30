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

  const AttendeesHorizontalList({
    super.key,
    required this.eventModel,
  });

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
            '  - id: ${attendee.id}, userName: ${attendee.userName}, customerUid: ${attendee.customerUid}, isAnonymous: ${attendee.isAnonymous}');
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Attendees (${attendees.length})',
                  style: const TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontSize: Dimensions.fontSizeLarge,
                    fontWeight: FontWeight.w600,
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
                    child: Text(
                      'See all',
                      style: const TextStyle(
                        color: AppThemeColor.darkGreenColor,
                        fontSize: Dimensions.fontSizeDefault,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      // Profile Picture
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppThemeColor.darkGreenColor,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: isAnon
                              ? Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.person_off,
                                    size: 25,
                                    color: Colors.grey,
                                  ),
                                )
                              : (customer?.profilePictureUrl != null
                                  ? Image.network(
                                      customer!.profilePictureUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey[300],
                                          child: const Icon(
                                            Icons.person,
                                            size: 25,
                                            color: Colors.grey,
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.person,
                                        size: 25,
                                        color: Colors.grey,
                                      ),
                                    )),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Name - Use attendee.userName for public display
                      SizedBox(
                        width: 60,
                        child: Text(
                          attendee.userName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppThemeColor.pureBlackColor,
                            fontSize: Dimensions.fontSizeSmall,
                            fontWeight: FontWeight.w500,
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
