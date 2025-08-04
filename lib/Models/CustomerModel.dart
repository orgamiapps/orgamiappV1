import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerModel {
  static String firebaseKey = 'Customers';
  String uid, name, email;
  String? username; // New username field
  String? profilePictureUrl;
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
  DateTime createdAt;

  CustomerModel({
    required this.uid,
    required this.name,
    required this.email,
    this.username,
    this.profilePictureUrl,
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
    required this.createdAt,
  });

  factory CustomerModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    print('User Info $d');
    return CustomerModel(
      uid: d['uid'],
      name: d['name'],
      email: d['email'],
      username: d['username'], // New field
      profilePictureUrl: d['profilePictureUrl'],
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
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  static Map<String, dynamic> getMap(CustomerModel d) {
    return {
      'uid': d.uid,
      'email': d.email,
      'name': d.name,
      'username': d.username, // New field
      'profilePictureUrl': d.profilePictureUrl,
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
      'createdAt': d.createdAt,
    };
  }
}
