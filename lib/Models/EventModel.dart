import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EventModel {
  static String firebaseKey = 'Events';

  String id, groupName, title, description, location, customerUid, imageUrl;

  DateTime selectedDateTime, eventGenerateTime;

  double latitude, longitude, radius;

  String status;

  bool private, getLocation;
  List<String> categories;
  bool isFeatured;
  DateTime? featureEndDate;

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
    this.categories = const [],
    this.isFeatured = false,
    this.featureEndDate,
  });

  factory EventModel.fromJson(dynamic parsedJson) {
    // Support both DocumentSnapshot and Map
    final data = parsedJson is Map
        ? parsedJson
        : (parsedJson.data() as Map<String, dynamic>);
    return EventModel(
      id: data['id'],
      groupName: data['groupName'],
      title: data['title'],
      description: data['description'],
      location: data['location'],
      imageUrl: data['imageUrl'],
      customerUid: data['customerUid'],
      status: data['status'],
      selectedDateTime: (data['selectedDateTime'] as Timestamp).toDate(),
      eventGenerateTime: (data['eventGenerateTime'] as Timestamp).toDate(),
      private: data['private'],
      getLocation: data['getLocation'] ?? false,
      latitude: data['latitude'] ?? 0.0,
      longitude: data['longitude'] ?? 0.0,
      radius: data['radius'] ?? 1.0,
      categories: (data.containsKey('categories') && data['categories'] != null)
          ? List<String>.from(data['categories'])
          : [],
      isFeatured: data['isFeatured'] ?? false,
      featureEndDate: data['featureEndDate'] != null
          ? (data['featureEndDate'] is Timestamp
              ? (data['featureEndDate'] as Timestamp).toDate()
              : DateTime.tryParse(data['featureEndDate'].toString()))
          : null,
    );
  }

  LatLng getLatLng() {
    return LatLng(latitude, longitude);
  }

  /// Returns a formatted display ID for the event
  String get displayId {
    // For word-based IDs (e.g., "SUNNY-42"), return as is
    if (id.contains('-') && id.split('-').length == 2) {
      return id;
    }
    // If the ID is numeric, format it with dashes for better readability
    if (id.length == 6 && int.tryParse(id) != null) {
      return '${id.substring(0, 3)}-${id.substring(3)}';
    }
    // For alphanumeric IDs, format as XXX-XXX
    if (id.length == 6) {
      return '${id.substring(0, 3)}-${id.substring(3)}';
    }
    // For timestamp-based IDs, return as is
    return id;
  }

  /// Returns the raw ID without formatting
  String get rawId => id;

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
    data['categories'] = categories;
    data['isFeatured'] = isFeatured;
    data['featureEndDate'] = featureEndDate;
    return data;
  }
}
