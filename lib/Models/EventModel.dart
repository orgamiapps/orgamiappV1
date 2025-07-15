import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EventModel {
  static String firebaseKey = 'Events';

  String id, groupName, title, description, location, customerUid, imageUrl;

  DateTime selectedDateTime, eventGenerateTime;

  double latitude, longitude, radius;

  String status;

  bool private, getLocation;

  LatLng getLatLngOfEvent() {
    return LatLng(latitude, longitude);
  }

  EventModel({
    required this.id,
    required this.groupName,
    required this.title,
    required this.description,
    required this.location,
    required this.customerUid,
    required this.imageUrl,
    required this.selectedDateTime,
    required this.eventGenerateTime,
    required this.status,
    required this.private,
    required this.getLocation,
    required this.radius,
    required this.latitude,
    required this.longitude,
  });

  factory EventModel.fromJson(parsedJson) {
    print('Event Model Data:  [38;5;246m${parsedJson['imageUrl']} [0m');
    return EventModel(
      id: parsedJson['id'],
      groupName: parsedJson['groupName'],
      title: parsedJson['title'],
      description: parsedJson['description'],
      location: parsedJson['location'],
      imageUrl: parsedJson['imageUrl'],
      customerUid: parsedJson['customerUid'],
      status: parsedJson['status'],
      selectedDateTime: (parsedJson['selectedDateTime'] as Timestamp).toDate(),
      eventGenerateTime:
          (parsedJson['eventGenerateTime'] as Timestamp).toDate(),
      private: parsedJson['private'],
      getLocation: parsedJson['getLocation'] ?? false,
      latitude: parsedJson['latitude'] ?? 0.0,
      longitude: parsedJson['longitude'] ?? 0.0,
      radius: parsedJson['radius'] ?? 1.0,
    );
  }

  LatLng getLatLng() {
    return LatLng(latitude, longitude);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};

    data['id'] = id;
    data['groupName'] = groupName;
    data['title'] = title;
    data['description'] = description;
    data['location'] = location;
    data['imageUrl'] = imageUrl;
    data['customerUid'] = customerUid;
    data['status'] = status;
    data['selectedDateTime'] = selectedDateTime;
    data['eventGenerateTime'] = eventGenerateTime;
    data['private'] = private;
    data['getLocation'] = getLocation;
    data['radius'] = radius;
    data['longitude'] = longitude;
    data['latitude'] = latitude;

    return data;
  }
}
