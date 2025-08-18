import 'package:cloud_firestore/cloud_firestore.dart';

class UserBadgeModel {
  static String firebaseKey = 'UserBadges';
  
  final String uid;
  final String userName;
  final String email;
  final String? profileImageUrl;
  final String? occupation;
  final String? location;
  final DateTime memberSince;
  final int eventsCreated;
  final int eventsAttended;
  final double totalDwellHours;
  final String badgeLevel;
  final List<String> achievements;
  final DateTime lastUpdated;
  
  UserBadgeModel({
    required this.uid,
    required this.userName,
    required this.email,
    this.profileImageUrl,
    this.occupation,
    this.location,
    required this.memberSince,
    required this.eventsCreated,
    required this.eventsAttended,
    required this.totalDwellHours,
    required this.badgeLevel,
    required this.achievements,
    required this.lastUpdated,
  });

  // Calculate badge level based on activities
  static String calculateBadgeLevel(int eventsCreated, int eventsAttended) {
    final totalActivity = eventsCreated + eventsAttended;
    
    if (totalActivity >= 100) return 'Master Organizer';
    if (totalActivity >= 50) return 'Senior Event Host';
    if (totalActivity >= 25) return 'Event Specialist';
    if (totalActivity >= 10) return 'Active Member';
    if (totalActivity >= 5) return 'Community Builder';
    return 'Event Explorer';
  }

  // Calculate badge color based on level
  String get badgeColor {
    switch (badgeLevel) {
      case 'Master Organizer':
        return '#FFD700'; // Gold
      case 'Senior Event Host':
        return '#C0C0C0'; // Silver
      case 'Event Specialist':
        return '#CD7F32'; // Bronze
      case 'Active Member':
        return '#4A90E2'; // Blue
      case 'Community Builder':
        return '#50C878'; // Green
      default:
        return '#9B59B6'; // Purple
    }
  }

  // Get achievements based on user stats
  static List<String> generateAchievements(int eventsCreated, int eventsAttended, double dwellHours) {
    List<String> achievements = [];
    
    if (eventsCreated >= 50) achievements.add('Master Creator');
    else if (eventsCreated >= 25) achievements.add('Event Creator');
    else if (eventsCreated >= 10) achievements.add('Active Creator');
    
    if (eventsAttended >= 50) achievements.add('Super Attendee');
    else if (eventsAttended >= 25) achievements.add('Regular Attendee');
    else if (eventsAttended >= 10) achievements.add('Event Explorer');
    
    if (dwellHours >= 100) achievements.add('Time Master');
    else if (dwellHours >= 50) achievements.add('Engagement Expert');
    
    if (eventsCreated >= 10 && eventsAttended >= 10) {
      achievements.add('Community Leader');
    }
    
    return achievements;
  }

  // Get formatted member duration
  String get membershipDuration {
    final now = DateTime.now();
    final difference = now.difference(memberSince);
    
    if (difference.inDays >= 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'}';
    } else if (difference.inDays >= 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'}';
    } else {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'}';
    }
  }

  // Create from Firestore document
  factory UserBadgeModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    return UserBadgeModel(
      uid: data['uid'] ?? '',
      userName: data['userName'] ?? '',
      email: data['email'] ?? '',
      profileImageUrl: data['profileImageUrl'],
      occupation: data['occupation'],
      location: data['location'],
      memberSince: (data['memberSince'] as Timestamp?)?.toDate() ?? DateTime.now(),
      eventsCreated: data['eventsCreated'] ?? 0,
      eventsAttended: data['eventsAttended'] ?? 0,
      totalDwellHours: (data['totalDwellHours'] ?? 0).toDouble(),
      badgeLevel: data['badgeLevel'] ?? 'Event Explorer',
      achievements: List<String>.from(data['achievements'] ?? []),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'userName': userName,
      'email': email,
      'profileImageUrl': profileImageUrl,
      'occupation': occupation,
      'location': location,
      'memberSince': Timestamp.fromDate(memberSince),
      'eventsCreated': eventsCreated,
      'eventsAttended': eventsAttended,
      'totalDwellHours': totalDwellHours,
      'badgeLevel': badgeLevel,
      'achievements': achievements,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  // QR payload for scanning user's badge to resolve tickets at an event
  String get badgeQrData => 'orgami_user_$uid';

  // Parse a user badge QR and return the user id if valid
  static String? parseBadgeQr(String data) {
    const prefix = 'orgami_user_';
    if (data.startsWith(prefix)) {
      return data.substring(prefix.length);
    }
    return null;
  }

  // Create badge from customer data and calculated stats
  static UserBadgeModel createFromUserData({
    required String uid,
    required String userName,
    required String email,
    String? profileImageUrl,
    String? occupation,
    String? location,
    required DateTime memberSince,
    required int eventsCreated,
    required int eventsAttended,
    required double totalDwellHours,
  }) {
    final badgeLevel = calculateBadgeLevel(eventsCreated, eventsAttended);
    final achievements = generateAchievements(eventsCreated, eventsAttended, totalDwellHours);
    
    return UserBadgeModel(
      uid: uid,
      userName: userName,
      email: email,
      profileImageUrl: profileImageUrl,
      occupation: occupation,
      location: location,
      memberSince: memberSince,
      eventsCreated: eventsCreated,
      eventsAttended: eventsAttended,
      totalDwellHours: totalDwellHours,
      badgeLevel: badgeLevel,
      achievements: achievements,
      lastUpdated: DateTime.now(),
    );
  }

  // Copy with method for updates
  UserBadgeModel copyWith({
    String? uid,
    String? userName,
    String? email,
    String? profileImageUrl,
    String? occupation,
    String? location,
    DateTime? memberSince,
    int? eventsCreated,
    int? eventsAttended,
    double? totalDwellHours,
    String? badgeLevel,
    List<String>? achievements,
    DateTime? lastUpdated,
  }) {
    return UserBadgeModel(
      uid: uid ?? this.uid,
      userName: userName ?? this.userName,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      occupation: occupation ?? this.occupation,
      location: location ?? this.location,
      memberSince: memberSince ?? this.memberSince,
      eventsCreated: eventsCreated ?? this.eventsCreated,
      eventsAttended: eventsAttended ?? this.eventsAttended,
      totalDwellHours: totalDwellHours ?? this.totalDwellHours,
      badgeLevel: badgeLevel ?? this.badgeLevel,
      achievements: achievements ?? this.achievements,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
