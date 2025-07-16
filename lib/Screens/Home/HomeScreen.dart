import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/ChoseDateTimeScreen.dart';
import 'package:orgami/Screens/Events/Widget/SingleEventListViewItem.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/AppConstants.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  double radiusInMiles = 0;
  List<String> selectedCategories = [];

  // Available categories
  final List<String> _allCategories = ['Educational', 'Professional', 'Other'];

  LatLng? currentLocation;
  Future<void> getCurrentLocation() async {
    try {
      await Geolocator.getCurrentPosition().then((value) {
        LatLng newLatLng = LatLng(
          value.latitude,
          value.longitude,
        );
        setState(() {
          currentLocation = newLatLng;
        });
      });
    } catch (e) {
      print('Getting error in current Location Fatching! ${e.toString()}');
    }
  }

  bool isInRadius(LatLng center, double radiusInFeet, LatLng point) {
    double radiusInMeters = radiusInFeet * 1609.34; // Convert miles to meters
    double earthRadius = 6378137; // Earth's radius in meters

    double dLat = radians(point.latitude - center.latitude);
    double dLng = radians(point.longitude - center.longitude);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(radians(center.latitude)) *
            cos(radians(point.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;

    return distance <= radiusInMeters;
  }

  double radians(double degrees) {
    return degrees * pi / 180;
  }

  double calculateDistance(LatLng start, LatLng end) {
    double earthRadius = 6378137; // Earth's radius in meters

    double dLat = radians(end.latitude - start.latitude);
    double dLng = radians(end.longitude - start.longitude);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(radians(start.latitude)) *
            cos(radians(end.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;

    return distance;
  }

  List<EventModel> filterEvents(
    List<EventModel> events,
  ) {
    List<EventModel> filteredEvents = events;

    // Filter by categories if any are selected
    if (selectedCategories.isNotEmpty) {
      filteredEvents = filteredEvents.where((event) {
        // Include events that match ANY selected category
        return event.categories
            .any((category) => selectedCategories.contains(category));
      }).toList();
    }

    // Filter by distance if location and radius are set
    if (currentLocation != null && radiusInMiles > 0) {
      filteredEvents = filteredEvents
          .where(
            (event) => isInRadius(
              currentLocation!,
              radiusInMiles,
              event.getLatLng(),
            ),
          )
          .toList()
        ..sort((a, b) {
          double distanceA = calculateDistance(currentLocation!, a.getLatLng());
          double distanceB = calculateDistance(currentLocation!, b.getLatLng());

          if (distanceA == distanceB) {
            return a.selectedDateTime.compareTo(b.selectedDateTime);
          } else {
            return distanceA.compareTo(distanceB);
          }
        });
    }

    return filteredEvents;
  }

  @override
  void initState() {
    getCurrentLocation();
    super.initState();
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
          _appBarView(),
          Expanded(child: _eventsView()),
        ],
      ),
    );
  }

  Widget _eventsView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Upcoming Events',
                style: TextStyle(
                  color: AppThemeColor.pureBlackColor,
                  fontWeight: FontWeight.w600,
                  fontSize: Dimensions.fontSizeExtraLarge,
                ),
              ),
              Row(
                children: [
                  // AppButtons.roundedButton(
                  //   iconData: FontAwesomeIcons.magnifyingGlass,
                  //   iconColor: AppThemeColor.pureWhiteColor,
                  //   backgroundColor: AppThemeColor.darkBlueColor,
                  // ),
                  // const SizedBox(
                  //   width: 5,
                  // ),
                  GestureDetector(
                    onTap: () {
                      RouterClass.nextScreenNormal(
                        context,
                        const ChoseDateTimeScreen(),
                      );
                    },
                    child: AppButtons.roundedButton(
                      iconData: Icons.add_chart,
                      iconColor: AppThemeColor.pureWhiteColor,
                      backgroundColor: AppThemeColor.darkGreenColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        // Category Filter Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter by Category',
                style: TextStyle(
                  color: AppThemeColor.pureBlackColor,
                  fontWeight: FontWeight.w600,
                  fontSize: Dimensions.fontSizeDefault,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _allCategories.length,
                  itemBuilder: (context, index) {
                    final category = _allCategories[index];
                    final isSelected = selectedCategories.contains(category);

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(
                          category,
                          style: TextStyle(
                            color: isSelected
                                ? AppThemeColor.pureWhiteColor
                                : AppThemeColor.pureBlackColor,
                            fontSize: Dimensions.fontSizeSmall,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedCategories.add(category);
                            } else {
                              selectedCategories.remove(category);
                            }
                          });
                        },
                        backgroundColor: AppThemeColor.pureWhiteColor,
                        selectedColor: AppThemeColor.darkGreenColor,
                        side: BorderSide(
                          color: isSelected
                              ? AppThemeColor.darkGreenColor
                              : AppThemeColor.grayColor,
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Text(
          'Filter Distance (${radiusInMiles > 0 ? AppConstants.getMilesSliderLabel(radiusInMiles) : 'Global'})',
          style: const TextStyle(
            color: AppThemeColor.pureBlackColor,
            fontWeight: FontWeight.w700,
            fontSize: Dimensions.fontSizeDefault,
          ),
        ),
        Slider(
          min: 0,
          max: 1000,
          value: radiusInMiles,
          // divisions: 7,
          label: AppConstants.getMilesSliderLabel(radiusInMiles),
          onChanged: (value) {
            setState(() {
              radiusInMiles = value;
            });
          },
        ),
        Expanded(child: _eventsListView()),
      ],
    );
  }

  Widget _eventsListView() {
    return FirestoreQueryBuilder(
      query: FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .orderBy('selectedDateTime', descending: false)
          .where('private', isEqualTo: false),
      pageSize: 500,
      builder: ((context,
          FirestoreQueryBuilderSnapshot<Map<String, dynamic>> snapshot, _) {
        if (snapshot.isFetching) {
          return SizedBox(
            height: _screenWidth,
            width: _screenWidth,
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Something Went Wrong ${snapshot.error}'));
        }

        if (snapshot.docs.isEmpty) {
          return const Center(child: Text('No Event Found!'));
        }

        List<EventModel> eventsList =
            snapshot.docs.map((e) => EventModel.fromJson(e)).toList();

        List<EventModel> neededEventList = [];

        for (var element in eventsList) {
          if (!element.selectedDateTime
              .add(
                const Duration(hours: 2),
              )
              .isBefore(DateTime.now())) {
            neededEventList.add(element);
          }
        }

        return ListView.builder(
            itemCount: filterEvents(neededEventList).length,
            shrinkWrap: true,
            itemBuilder: (listContext, listIndex) {
              final EventModel d = filterEvents(neededEventList)[listIndex];
              return SingleEventListViewItem(eventModel: d);
            });
      }),
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
