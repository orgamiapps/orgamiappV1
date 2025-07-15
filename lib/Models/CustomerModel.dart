import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerModel {
  static String firebaseKey = 'Customers';
  String uid, name, email;
  String? profilePictureUrl;
  String? bio;
  DateTime createdAt;

  CustomerModel({
    required this.uid,
    required this.name,
    required this.email,
    this.profilePictureUrl,
    this.bio,
    required this.createdAt,
  });

  factory CustomerModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    print('User Info $d');
    return CustomerModel(
      uid: d['uid'],
      name: d['name'],
      email: d['email'],
      profilePictureUrl: d['profilePictureUrl'],
      bio: d['bio'],
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }
  static Map<String, dynamic> getMap(CustomerModel d) {
    return {
      'uid': d.uid,
      'email': d.email,
      'name': d.name,
      'profilePictureUrl': d.profilePictureUrl,
      'bio': d.bio,
      'createdAt': d.createdAt,
    };
  }
}
