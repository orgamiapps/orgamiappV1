import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter/material.dart';

// IMPORTANT: Ensure Firestore security rules allow authenticated users to read non-private events:
// match /Events/{eventId} {
//   allow read: if request.auth != null &&
//     (resource.data.customerUid == request.auth.uid || resource.data.private == false);
//   allow write: if request.auth != null && request.auth.uid == resource.data.customerUid;
// }
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/Widget/SingleEventListViewItem.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';

class SearchEventsScreen extends StatefulWidget {
  const SearchEventsScreen({super.key});

  @override
  State<SearchEventsScreen> createState() => _SearchEventsScreenState();
}

class _SearchEventsScreenState extends State<SearchEventsScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final TextEditingController _searchController = TextEditingController();

  String _searchValue = '';

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
          _appBarView(),
          _searchView(),
          Expanded(child: _eventsView()),
        ],
      ),
    );
  }

  Widget _searchView() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: TextFormField(
        controller: _searchController,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Type event name...',
          labelText: 'Search',
          contentPadding: EdgeInsets.symmetric(vertical: 5, horizontal: 20),
        ),
        onChanged: (newVal) {
          if (newVal.isNotEmpty) {
            setState(() {
              _searchValue = newVal;
            });
          } else {
            setState(() {
              _searchValue = '';
            });
          }
        },
      ),
    );
  }

  Widget _eventsView() {
    return Column(
      children: [
        // Padding(
        //   padding: const EdgeInsets.symmetric(horizontal: 20.0),
        //   child: Row(
        //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //     children: [
        //       const Text(
        //         'Upcoming Events',
        //         style: TextStyle(
        //           color: AppThemeColor.pureBlackColor,
        //           fontWeight: FontWeight.w600,
        //           fontSize: Dimensions.fontSizeExtraLarge,
        //         ),
        //       ),
        //       Row(
        //         children: [
        //           AppButtons.roundedButton(
        //             iconData: FontAwesomeIcons.magnifyingGlass,
        //             iconColor: AppThemeColor.pureWhiteColor,
        //             backgroundColor: AppThemeColor.darkBlueColor,
        //           ),
        //           const SizedBox(
        //             width: 5,
        //           ),
        //           GestureDetector(
        //             onTap: () {
        //               RouterClass.nextScreenNormal(
        //                 context,
        //                 const ChoseDateTimeScreen(),
        //               );
        //             },
        //             child: AppButtons.roundedButton(
        //               iconData: Icons.add_chart,
        //               iconColor: AppThemeColor.pureWhiteColor,
        //               backgroundColor: AppThemeColor.darkGreenColor,
        //             ),
        //           ),
        //         ],
        //       ),
        //     ],
        //   ),
        // ),
        // const SizedBox(
        //   height: 20,
        // ),
        Expanded(child: _eventsListView()),
      ],
    );
  }

  Widget _eventsListView() {
    // Create a stream for the Firestore query
    Stream<QuerySnapshot> eventsStream = FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .where('private', isEqualTo: false)
        .orderBy('selectedDateTime', descending: false)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: eventsStream,
      builder: (context, snapshot) {
        // Show loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: _screenWidth,
            width: _screenWidth,
          );
        }

        // Show error state with retry button
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load events. Check your connection or permissions.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    // Force rebuild to retry the stream
                    setState(() {});
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkGreenColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Show empty state
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No Event Found!'));
        }

        // Process events data
        List<EventModel> eventsList = snapshot.data!.docs
            .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
            .toList();

        List<EventModel> neededEventList = [];

        for (var element in eventsList) {
          if (element.title
                  .toLowerCase()
                  .split(_searchValue.toLowerCase())
                  .length >
              1) {
            neededEventList.add(element);
          }
        }

        return ListView.builder(
            itemCount: neededEventList.length,
            shrinkWrap: true,
            itemBuilder: (listContext, listIndex) {
              final EventModel d = neededEventList[listIndex];
              if (d.selectedDateTime.add(const Duration(hours: 3)).isAfter(
                    DateTime.now(),
                  )) {
                return SingleEventListViewItem(eventModel: d);
              } else {
                return const SizedBox();
              }
            });
      },
    );
  }

  Widget _appBarView() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(
            Images.inAppLogo,
            width: _screenWidth / 2.5,
          ),
          // AppButtons.button1(
          //   width: 100,
          //   height: 40,
          //   buttonLoading: false,
          //   label: 'Quick Sign In',
          //   labelSize: Dimensions.fontSizeDefault,
          // ),
          // AppButtons.roundedButton(
          //   iconData: FontAwesomeIcons.qrcode,
          //   iconColor: AppThemeColor.pureWhiteColor,
          //   backgroundColor: AppThemeColor.darkBlueColor,
          // ),
        ],
      ),
    );
  }
}
