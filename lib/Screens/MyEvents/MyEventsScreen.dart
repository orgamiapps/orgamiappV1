import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/Widget/SingleEventListViewItem.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final FirebaseFirestore _fireStore = FirebaseFirestore.instance;

  int selectedTab = 1;

  bool showConfirmationTab = false;

  List<AttendanceModel> attendanceList = [];
  List<AttendanceModel> preRegisteredAttendanceList = [];

  late StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
      _attendanceSubscription;
  late StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
      _preRegisteredSubscription;

  bool signedInEvent({required String eventId}) {
    bool eventSignedIn = false;
    for (var element in attendanceList) {
      if (element.eventId == eventId) {
        eventSignedIn = true;
      }
    }

    return eventSignedIn;
  }

  bool preRegisteredEvent({required String eventId}) {
    bool eventPreRegistered = false;
    for (var element in preRegisteredAttendanceList) {
      if (element.eventId == eventId) {
        eventPreRegistered = true;
      }
    }

    return eventPreRegistered;
  }

  @override
  void initState() {
    super.initState();
    _attendanceSubscription = _fireStore
        .collection(AttendanceModel.firebaseKey)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        attendanceList = snapshot.docs
            .map((doc) => AttendanceModel.fromJson(doc.data()))
            .toList();
      });
    });

    _preRegisteredSubscription = _fireStore
        .collection(AttendanceModel.registerFirebaseKey)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        preRegisteredAttendanceList = snapshot.docs
            .map((doc) => AttendanceModel.fromJson(doc.data()))
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _attendanceSubscription.cancel();
    _preRegisteredSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.pureWhiteColor,
      body: SafeArea(
        child: _bodyView(),
      ),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      width: _screenWidth,
      height: _screenHeight,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child:
                AppAppBarView.appBarView(context: context, title: 'My Events'),
          ),
          _tobTabBar(),
          Expanded(
            child: _eventsHistoryView(),
          ),
        ],
      ),
    );
  }

  Widget _eventsHistoryView() {
    return Container(
      child: FirestoreQueryBuilder(
        pageSize: 500,
        query: _fireStore
            .collection(EventModel.firebaseKey)
            .where('customerUid',
                isEqualTo: CustomerController.logeInCustomer!.uid)
            .orderBy(
              'selectedDateTime',
              descending: false,
            ),
        builder: ((context,
            FirestoreQueryBuilderSnapshot<Map<String, dynamic>> snapshot, _) {
          if (snapshot.isFetching) {
            return const SizedBox();
          }

          if (snapshot.hasError) {
            return Center(
                child: Text('Something went wrong ${snapshot.error}'));
          }

          if (snapshot.docs.isEmpty) {
            return const Center(child: Text('No Event found!'));
          }

          List<EventModel> EventsList = snapshot.docs
              .map((e) => EventModel.fromJson(e))
              .toList()
            ..sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));

          if (selectedTab == 1) {
            List<EventModel> neededEventsList = [];
            for (var element in EventsList) {
              if (element.customerUid ==
                  CustomerController.logeInCustomer!.uid) {
                neededEventsList.add(element);
              }
            }
            EventsList = neededEventsList;
          } else if (selectedTab == 3) {
            List<EventModel> neededEventsList = [];
            for (var element in EventsList) {
              if (preRegisteredEvent(eventId: element.id)) {
                neededEventsList.add(element);
              }
            }
            EventsList = neededEventsList;
          } else {
            List<EventModel> neededEventsList = [];
            for (var element in EventsList) {
              if (signedInEvent(eventId: element.id)) {
                neededEventsList.add(element);
              }
            }
            EventsList = neededEventsList;
          }

          if (EventsList.isEmpty) {
            return const Center(child: Text('No Event found!'));
          }

          return ListView.builder(
              itemCount: EventsList.length,
              scrollDirection: Axis.vertical,
              shrinkWrap: true,
              itemBuilder: (listContext, listIndex) {
                final EventModel d = EventsList[listIndex];
                return SingleEventListViewItem(eventModel: d);
              });
        }),
      ),
    );
  }

  Widget _tobTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        children: [
          _singleTabBarView(label: 'Created', index: 1),
          _singleTabBarView(label: 'Attended', index: 2),
          _singleTabBarView(label: 'Registered', index: 3),
        ],
      ),
    );
  }

  Widget _singleTabBarView({required String label, required int index}) {
    bool selectedOne = selectedTab == index;
    return Expanded(
        child: GestureDetector(
      onTap: () {
        setState(() {
          selectedTab = index;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selectedOne
              ? AppThemeColor.darkBlueColor
              : AppThemeColor.darkGreenColor,
        ),
        child: Center(
            child: Text(
          label,
          style: const TextStyle(
            color: AppThemeColor.pureWhiteColor,
            fontSize: Dimensions.fontSizeDefault,
            fontWeight: FontWeight.w600,
          ),
        )),
      ),
    ));
  }
}
