import 'package:cloud_firestore/cloud_firestore.dart';

class BadgeModel {
  static String firebaseKey = 'UserBadges';

  String userId;
  String userName;
  String userEmail;
  int eventsCreated;
  int eventsAttended;
  DateTime memberSince;
  String? profileImageUrl;
  String badgeLevel; // 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond'
  int totalPoints;
  DateTime lastUpdated;
  
  // Additional stats for enhanced badge
  int totalTicketsIssued;
  int totalAttendeeCount;
  double averageEventRating;
  List<String> categories; // Event categories user is active in
  int consecutiveMonthsActive;
  
  BadgeModel({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.eventsCreated,
    required this.eventsAttended,
    required this.memberSince,
    this.profileImageUrl,
    this.badgeLevel = 'Bronze',
    this.totalPoints = 0,
    required this.lastUpdated,
    this.totalTicketsIssued = 0,
    this.totalAttendeeCount = 0,
    this.averageEventRating = 0.0,
    this.categories = const [],
    this.consecutiveMonthsActive = 0,
  });

  factory BadgeModel.fromFirestore(DocumentSnapshot snap) {
    Map data = snap.data() as Map<dynamic, dynamic>;
    return BadgeModel(
      userId: data['userId'],
      userName: data['userName'],
      userEmail: data['userEmail'],
      eventsCreated: data['eventsCreated'] ?? 0,
      eventsAttended: data['eventsAttended'] ?? 0,
      memberSince: (data['memberSince'] as Timestamp).toDate(),
      profileImageUrl: data['profileImageUrl'],
      badgeLevel: data['badgeLevel'] ?? 'Bronze',
      totalPoints: data['totalPoints'] ?? 0,
      lastUpdated: (data['lastUpdated'] as Timestamp).toDate(),
      totalTicketsIssued: data['totalTicketsIssued'] ?? 0,
      totalAttendeeCount: data['totalAttendeeCount'] ?? 0,
      averageEventRating: data['averageEventRating']?.toDouble() ?? 0.0,
      categories: List<String>.from(data['categories'] ?? []),
      consecutiveMonthsActive: data['consecutiveMonthsActive'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'eventsCreated': eventsCreated,
      'eventsAttended': eventsAttended,
      'memberSince': Timestamp.fromDate(memberSince),
      'profileImageUrl': profileImageUrl,
      'badgeLevel': badgeLevel,
      'totalPoints': totalPoints,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'totalTicketsIssued': totalTicketsIssued,
      'totalAttendeeCount': totalAttendeeCount,
      'averageEventRating': averageEventRating,
      'categories': categories,
      'consecutiveMonthsActive': consecutiveMonthsActive,
    };
  }

  // Calculate badge level based on total points
  String calculateBadgeLevel() {
    if (totalPoints >= 10000) return 'Diamond';
    if (totalPoints >= 5000) return 'Platinum';
    if (totalPoints >= 2000) return 'Gold';
    if (totalPoints >= 500) return 'Silver';
    return 'Bronze';
  }

  // Calculate total points based on activities
  int calculateTotalPoints() {
    int points = 0;
    
    // Points for creating events (50 points each)
    points += eventsCreated * 50;
    
    // Points for attending events (20 points each)
    points += eventsAttended * 20;
    
    // Points for total attendees at their events (2 points per attendee)
    points += totalAttendeeCount * 2;
    
    // Points for consecutive months active (100 points per month)
    points += consecutiveMonthsActive * 100;
    
    // Bonus points for high average rating (500 points if rating >= 4.5)
    if (averageEventRating >= 4.5) points += 500;
    
    // Bonus for being active in multiple categories
    points += categories.length * 100;
    
    return points;
  }

  // Get badge color based on level
  String getBadgeColor() {
    switch (badgeLevel) {
      case 'Diamond':
        return '#B9F2FF';
      case 'Platinum':
        return '#E5E4E2';
      case 'Gold':
        return '#FFD700';
      case 'Silver':
        return '#C0C0C0';
      default:
        return '#CD7F32';
    }
  }

  // Get badge gradient colors
  List<String> getBadgeGradient() {
    switch (badgeLevel) {
      case 'Diamond':
        return ['#B9F2FF', '#00BFFF', '#87CEEB'];
      case 'Platinum':
        return ['#E5E4E2', '#C0C0C0', '#B8B8B8'];
      case 'Gold':
        return ['#FFD700', '#FFA500', '#FF8C00'];
      case 'Silver':
        return ['#C0C0C0', '#A9A9A9', '#808080'];
      default:
        return ['#CD7F32', '#D2691E', '#8B4513'];
    }
  }

  // Get points needed for next level
  int getPointsForNextLevel() {
    switch (badgeLevel) {
      case 'Bronze':
        return 500 - totalPoints;
      case 'Silver':
        return 2000 - totalPoints;
      case 'Gold':
        return 5000 - totalPoints;
      case 'Platinum':
        return 10000 - totalPoints;
      default:
        return 0; // Diamond is max level
    }
  }

  // Get next badge level
  String getNextBadgeLevel() {
    switch (badgeLevel) {
      case 'Bronze':
        return 'Silver';
      case 'Silver':
        return 'Gold';
      case 'Gold':
        return 'Platinum';
      case 'Platinum':
        return 'Diamond';
      default:
        return 'Diamond'; // Already at max
    }
  }
}