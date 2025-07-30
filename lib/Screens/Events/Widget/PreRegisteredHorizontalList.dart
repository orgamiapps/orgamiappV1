import 'package:flutter/material.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';

class PreRegisteredHorizontalList extends StatefulWidget {
  final EventModel eventModel;

  const PreRegisteredHorizontalList({
    super.key,
    required this.eventModel,
  });

  @override
  State<PreRegisteredHorizontalList> createState() =>
      _PreRegisteredHorizontalListState();
}

class _PreRegisteredHorizontalListState
    extends State<PreRegisteredHorizontalList> {
  List<AttendanceModel> preRegistered = [];
  List<CustomerModel> customerDetails = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreRegistered();
  }

  Future<void> _loadPreRegistered() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Get all pre-registered for this event
      final preRegisteredList =
          await FirebaseFirestoreHelper().getRegisterAttendance(
        eventId: widget.eventModel.id,
      );

      // Get customer details for each pre-registered (limit to first 10 for performance)
      List<CustomerModel> customers = [];
      for (var attendee in preRegisteredList.take(10)) {
        final customer = await FirebaseFirestoreHelper().getSingleCustomer(
          customerId: attendee.customerUid,
        );
        if (customer != null) {
          customers.add(customer);
        }
      }

      setState(() {
        preRegistered = preRegisteredList;
        customerDetails = customers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error loading pre-registered: $e');
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

    if (preRegistered.isEmpty) {
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
                  'Pre-Registered (${preRegistered.length})',
                  style: const TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontSize: Dimensions.fontSizeLarge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (preRegistered.length > 5)
                  GestureDetector(
                    onTap: () {
                      // TODO: Implement see all pre-registered screen if needed
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
              itemCount: preRegistered.length > 5 ? 5 : preRegistered.length,
              itemBuilder: (context, index) {
                final attendee = preRegistered[index];
                final customer = customerDetails.firstWhere(
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
                              : (customer.profilePictureUrl != null
                                  ? Image.network(
                                      customer.profilePictureUrl!,
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
                      // Name
                      SizedBox(
                        width: 60,
                        child: Text(
                          isAnon
                              ? 'Anonymous'
                              : (attendee.customerUid == 'without_login'
                                  ? attendee.userName
                                  : customer.name),
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
