import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CustomerModel {
  static String firebaseKey = 'Customers';
  String uid, name, email;
  String? username; // New username field
  String? profilePictureUrl;
  String? bannerUrl;
  String? bio;
  String? phoneNumber;
  int? age;
  String? gender;
  String? location;
  String? occupation;
  String? company;
  String? website;
  String? socialMediaLinks;
  bool isDiscoverable; // New field for user search privacy
  List<String> favorites; // New field for saved events
  DateTime createdAt;
  int eventsCreated; // Track number of events created by user
  int groupsCreated; // Track number of groups created by user

  CustomerModel({
    required this.uid,
    required this.name,
    required this.email,
    this.username,
    this.profilePictureUrl,
    this.bannerUrl,
    this.bio,
    this.phoneNumber,
    this.age,
    this.gender,
    this.location,
    this.occupation,
    this.company,
    this.website,
    this.socialMediaLinks,
    this.isDiscoverable = true, // Default to discoverable
    this.favorites = const [], // Default to empty list for saved events
    required this.createdAt,
    this.eventsCreated = 0, // Default to 0 events created
    this.groupsCreated = 0, // Default to 0 groups created
  });

  factory CustomerModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    if (kDebugMode) {
      debugPrint('User Info $d');
    }

    // Robust createdAt parsing with safe fallback
    DateTime parsedCreatedAt = DateTime.now();
    final rawCreatedAt = d['createdAt'];
    if (rawCreatedAt is Timestamp) {
      parsedCreatedAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is DateTime) {
      parsedCreatedAt = rawCreatedAt;
    } else if (rawCreatedAt is String) {
      parsedCreatedAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    }

    return CustomerModel(
      uid: d['uid'],
      name: d['name'],
      email: d['email'],
      username: d['username'], // New field
      profilePictureUrl: d['profilePictureUrl'],
      bannerUrl: d['bannerUrl'],
      bio: d['bio'],
      phoneNumber: d['phoneNumber'],
      age: d['age'],
      gender: d['gender'],
      location: d['location'],
      occupation: d['occupation'],
      company: d['company'],
      website: d['website'],
      socialMediaLinks: d['socialMediaLinks'],
      isDiscoverable:
          d['isDiscoverable'] ??
          true, // Default to true for backward compatibility
      favorites: List<String>.from(d['favorites'] ?? []), // Saved events field
      createdAt: parsedCreatedAt,
      eventsCreated: d['eventsCreated'] ?? 0, // Default to 0 for backward compatibility
      groupsCreated: d['groupsCreated'] ?? 0, // Default to 0 for backward compatibility
    );
  }

  static Map<String, dynamic> getMap(CustomerModel d) {
    return {
      'uid': d.uid,
      'email': d.email,
      'name': d.name,
      'username': d.username, // New field
      'profilePictureUrl': d.profilePictureUrl,
      'bannerUrl': d.bannerUrl,
      'bio': d.bio,
      'phoneNumber': d.phoneNumber,
      'age': d.age,
      'gender': d.gender,
      'location': d.location,
      'occupation': d.occupation,
      'company': d.company,
      'website': d.website,
      'socialMediaLinks': d.socialMediaLinks,
      'isDiscoverable': d.isDiscoverable,
      'favorites': d.favorites, // Saved events field
      'createdAt': d.createdAt,
      'eventsCreated': d.eventsCreated, // Track events created
      'groupsCreated': d.groupsCreated, // Track groups created
    };
  }
}
