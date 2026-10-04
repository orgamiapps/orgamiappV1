import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      eventsCreated:
          d['eventsCreated'] ?? 0, // Default to 0 for backward compatibility
      groupsCreated:
          d['groupsCreated'] ?? 0, // Default to 0 for backward compatibility
    );
  }

  /// Allowlisted card projection. Extra server fields are deliberately ignored.
  factory CustomerModel.fromPublicProfile(Map<String, dynamic> data) =>
      CustomerModel(
        uid: data['uid'] as String? ?? '',
        name: data['name'] as String? ?? 'Attendus member',
        email: '',
        username: data['username'] as String?,
        profilePictureUrl: data['profilePictureUrl'] as String?,
        bannerUrl: data['bannerUrl'] as String?,
        bio: data['bio'] as String?,
        isDiscoverable: data['isDiscoverable'] == true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

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

  /// Auth enrichment only fills absent values; a saved profile wins over Auth.
  static Map<String, dynamic> missingAuthProfileFields(
    CustomerModel current, {
    String? name,
    String? phoneNumber,
    String? profilePictureUrl,
  }) => {
    if (current.name.trim().isEmpty && name?.trim().isNotEmpty == true)
      'name': name!.trim(),
    if (current.phoneNumber?.trim().isNotEmpty != true &&
        phoneNumber?.trim().isNotEmpty == true)
      'phoneNumber': phoneNumber!.trim(),
    if (current.profilePictureUrl?.trim().isNotEmpty != true &&
        profilePictureUrl?.trim().isNotEmpty == true)
      'profilePictureUrl': profilePictureUrl!.trim(),
  };

  static Map<String, dynamic> getPublicMap(CustomerModel customer) => {
    'uid': customer.uid,
    'name': customer.name,
    'username': customer.username,
    'profilePictureUrl': customer.profilePictureUrl,
    'bannerUrl': customer.bannerUrl,
    'bio': customer.bio,
    'isDiscoverable': customer.isDiscoverable,
  };
}

/// An immutable snapshot of normalized, rendered form values. Editors submit
/// only changes to their own controls, never a cached Customer document.
class ProfileEditSnapshot {
  static const profileFields = {
    'name',
    'email',
    'username',
    'phoneNumber',
    'age',
    'gender',
    'location',
    'occupation',
    'company',
    'website',
    'bio',
    'socialMediaLinks',
    'isDiscoverable',
  };
  static const notificationFields = {
    'eventReminders',
    'messagesAll',
    'generalNotifications',
  };

  ProfileEditSnapshot.profile(Map<String, dynamic> values)
    : this._(values, profileFields);
  ProfileEditSnapshot.notifications(Map<String, dynamic> values)
    : this._(values, notificationFields);

  ProfileEditSnapshot._(Map<String, dynamic> values, Set<String> allowed)
    : _values = Map.unmodifiable(values) {
    if (values.keys.any((key) => !allowed.contains(key)) ||
        values.values.any(
          (value) =>
              value != null &&
              value is! String &&
              value is! bool &&
              value is! int,
        )) {
      throw ArgumentError('Only normalized editable form values are supported');
    }
  }

  final Map<String, dynamic> _values;

  Map<String, dynamic> changes(Map<String, dynamic> current) {
    if (current.length != _values.length ||
        current.keys.any((key) => !_values.containsKey(key))) {
      throw StateError('The loaded form does not match the submitted controls');
    }
    return {
      for (final entry in current.entries)
        if (entry.value != _values[entry.key]) entry.key: entry.value,
    };
  }
}

/// Social links are stored as one JSON field. Merge only edited controls into
/// freshly read JSON so unknown links and another session's changes survive.
class SocialLinksEditSnapshot {
  SocialLinksEditSnapshot(Map<String, String> initial)
    : _initial = Map.unmodifiable(initial);
  final Map<String, String> _initial;

  Map<String, String> changes(Map<String, String> current) {
    if (current.length != _initial.length ||
        current.keys.any((key) => !_initial.containsKey(key))) {
      throw StateError('Social controls changed after load');
    }
    return {
      for (final entry in current.entries)
        if (entry.value != _initial[entry.key]) entry.key: entry.value,
    };
  }

  static String? merge(Object? stored, Map<String, String> dirty) {
    Map<String, dynamic> current = {};
    if (stored != null && stored != '') {
      if (stored is! String) {
        throw const FormatException('Stored social links are invalid');
      }
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Stored social links are invalid');
      }
      current = Map.of(decoded);
    }
    for (final entry in dirty.entries) {
      if (entry.value.isEmpty) {
        current.remove(entry.key);
      } else {
        current[entry.key] = entry.value;
      }
    }
    return current.isEmpty ? null : jsonEncode(current);
  }
}
