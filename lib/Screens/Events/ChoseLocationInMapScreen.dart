import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/Screens/Events/CreateEventScreen.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';

class ChoseLocationInMapScreen extends StatefulWidget {
  final DateTime selectedDateTime;
  const ChoseLocationInMapScreen({super.key, required this.selectedDateTime});

  @override
  State<ChoseLocationInMapScreen> createState() =>
      _ChoseLocationInMapScreenState();
}

class _ChoseLocationInMapScreenState extends State<ChoseLocationInMapScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;
  late GoogleMapController mapController;
  LatLng? selectedLocation;
  double radius = 10.0; // Default radius

  Set<Marker> markers = {};

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    await Geolocator.getCurrentPosition().then((value) {
      LatLng newLatLng = LatLng(
        value.latitude,
        value.longitude,
      );
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newLatLng,
            zoom: 15,
          ),
        ),
      );
      _addMarker(newLatLng);
      print(
          'Current Location is ${value.latitude} and ${value.longitude} and ${value.floor}');
    });
  }

  void _addMarker(LatLng latLng) {
    setState(() {
      markers.clear(); // Clear existing markers
      markers.add(
        Marker(
          markerId: const MarkerId('selected-location'),
          position: latLng,
          infoWindow: const InfoWindow(
            title: 'Selected Location',
          ),
        ),
      );
      selectedLocation = latLng;
    });
  }

  @override
  void initState() {
    _getCurrentLocation();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: Text('Select Location and Radius'),
      // ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,

      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 100),
        child: FloatingActionButton(
          backgroundColor: AppThemeColor.pureWhiteColor,
          onPressed: () async {
            // await Location.
            // _getAddressFromLatLng();
            _getCurrentLocation();
          },
          child: const Icon(
            Icons.my_location,
            color: AppThemeColor.darkGreenColor,
          ),
        ),
      ),
      body: SafeArea(
        child: SizedBox(
          height: _screenHeight,
          width: _screenWidth,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: AppAppBarView.appBarView(
                  context: context,
                  title: 'Select Location and Radius',
                ),
              ),
              Expanded(
                child: GoogleMap(
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: true,
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: selectedLocation != null
                        ? selectedLocation!
                        : const LatLng(37.42796133580664, -122.085749655962),
                    zoom: 12.0,
                  ),
                  onTap: _onMapTapped,
                  markers: markers,
                ),
              ),
              if (selectedLocation != null)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Select Radius (Feet)'),
                          Text(
                            '${radius.round()} Feet',
                            style: const TextStyle(
                              color: AppThemeColor.dullFontColor,
                              fontSize: Dimensions.fontSizeDefault,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: radius,
                        min: 10,
                        max: 1000,
                        // divisions: 10,
                        onChanged: (value) {
                          setState(() {
                            radius = value;
                          });
                        },
                      ),
                      GestureDetector(
                        onTap: () {
                          // Handle saving the selected location and radius
                          print('Selected Location: $selectedLocation');
                          print('Selected Radius: $radius km');

                          RouterClass.nextScreenNormal(
                            context,
                            CreateEventScreen(
                                selectedDateTime: widget.selectedDateTime,
                                selectedLocation: selectedLocation!,
                                radios: radius),
                          );
                        },
                        child: AppButtons.button1(
                          width: _screenWidth,
                          height: 45,
                          buttonLoading: false,
                          label: 'Continue',
                          labelSize: Dimensions.fontSizeLarge,
                        ),
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

  void _onMapCreated(GoogleMapController controller) {
    setState(() {
      mapController = controller;
    });
  }

  void _onMapTapped(LatLng location) {
    _addMarker(location);
    mapController.moveCamera(CameraUpdate.newLatLng(location));
  }
  // late GoogleMapController mapController;
  // LatLng? selectedLocation;
  // double radius = 5.0; // Default radius
  //
  // @override
  // Widget build(BuildContext context) {
  //   return Scaffold(
  //     appBar: AppBar(
  //       title: Text('Select Location and Radius'),
  //     ),
  //     body: Stack(
  //       children: [
  //         GoogleMap(
  //           onMapCreated: _onMapCreated,
  //           initialCameraPosition: CameraPosition(
  //             target: LatLng(37.42796133580664, -122.085749655962),
  //             zoom: 12.0,
  //           ),
  //           onTap: _onMapTapped,
  //         ),
  //         Positioned(
  //           bottom: 20.0,
  //           left: 20.0,
  //           right: 20.0,
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.stretch,
  //             children: [
  //               Text('Select Radius (km)'),
  //               Slider(
  //                 value: radius,
  //                 min: 1,
  //                 max: 10,
  //                 divisions: 9,
  //                 onChanged: (value) {
  //                   setState(() {
  //                     radius = value;
  //                   });
  //                 },
  //               ),
  //               GestureDetector(
  //                 onTap: () {
  //                   // Handle saving the selected location and radius
  //                   print('Selected Location: $selectedLocation');
  //                   print('Selected Radius: $radius km');
  //                 },
  //                 child: AppButtons.button1(
  //                   width: _screenWidth,
  //                   height: 45,
  //                   buttonLoading: false,
  //                   label: 'Save',
  //                   labelSize: Dimensions.fontSizeLarge,
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
  //
  // void _onMapCreated(GoogleMapController controller) {
  //   setState(() {
  //     mapController = controller;
  //   });
  // }
  //
  // void _onMapTapped(LatLng location) {
  //   setState(() {
  //     selectedLocation = location;
  //   });
  //   mapController!.moveCamera(CameraUpdate.newLatLng(location));
  // }
}
