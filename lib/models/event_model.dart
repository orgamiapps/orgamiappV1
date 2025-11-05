import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EventModel {
  static String firebaseKey = 'Events';

  String id, groupName, title, description, location, customerUid, imageUrl;
  String? locationName; // Optional display name for the venue/location

  DateTime selectedDateTime, eventGenerateTime;

  double latitude, longitude, radius;

  String status;

  bool private, getLocation;
  List<String> categories;
  bool isFeatured;
  DateTime? featureEndDate;
  bool ticketsEnabled;
  int maxTickets;
  int issuedTickets;
  double? ticketPrice; // Price per ticket in USD
  bool ticketUpgradeEnabled; // Whether skip-the-line upgrades are available
  double?
  ticketUpgradePrice; // Price to upgrade to skip-the-line (total price, not additional)
  int eventDuration; // Duration in hours
  List<String> coHosts; // Array of user IDs who are co-hosts
  String? organizationId; // Optional organization context for the event
  List<String>
  accessList; // For private events outside org or additional invitees

  // Sign-in methods configuration
  // Legacy support: ['qr_code', 'manual_code', 'geofence', 'facial_recognition']
  List<String> signInMethods; 
  
  // New security tier system
  // Options: 'most_secure', 'geofence_only', 'regular', 'all'
  String? signInSecurityTier;
  
  String? manualCode; // Custom manual code for the event

  // Live Quiz configuration
  bool hasLiveQuiz; // Whether this event has a live quiz
  String? liveQuizId; // ID of the associated live quiz

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
    this.locationName,
    this.categories = const [],
    this.isFeatured = false,
    this.featureEndDate,
    this.ticketsEnabled = false,
    this.maxTickets = 0,
    this.issuedTickets = 0,
    this.ticketPrice,
    this.ticketUpgradeEnabled = false,
    this.ticketUpgradePrice,
    this.eventDuration = 2, // Default 2 hours
    this.coHosts = const [],
    this.organizationId,
    this.accessList = const [],
    this.signInMethods = const [
      'qr_code',
      'manual_code',
    ], // Default methods (legacy support)
    this.signInSecurityTier = 'regular', // Default to regular tier
    this.manualCode,
    this.hasLiveQuiz = false,
    this.liveQuizId,
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
      locationName: data['locationName'],
      imageUrl: data['imageUrl'],
      customerUid: data['customerUid'],
      status: data['status'],
      selectedDateTime: data['selectedDateTime'] is Timestamp
          ? (data['selectedDateTime'] as Timestamp).toDate()
          : DateTime.tryParse(data['selectedDateTime'].toString()) ??
                DateTime.now(),
      eventGenerateTime: data['eventGenerateTime'] is Timestamp
          ? (data['eventGenerateTime'] as Timestamp).toDate()
          : DateTime.tryParse(data['eventGenerateTime'].toString()) ??
                DateTime.now(),
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
      ticketsEnabled: data['ticketsEnabled'] ?? false,
      maxTickets: data['maxTickets'] ?? 0,
      issuedTickets: data['issuedTickets'] ?? 0,
      ticketPrice: data['ticketPrice']?.toDouble(),
      ticketUpgradeEnabled: data['ticketUpgradeEnabled'] ?? false,
      ticketUpgradePrice: data['ticketUpgradePrice']?.toDouble(),
      eventDuration: data['eventDuration'] ?? 2,
      coHosts: (data.containsKey('coHosts') && data['coHosts'] != null)
          ? List<String>.from(data['coHosts'])
          : [],
      organizationId: data['organizationId'],
      accessList: (data.containsKey('accessList') && data['accessList'] != null)
          ? List<String>.from(data['accessList'])
          : [],
      signInMethods:
          (data.containsKey('signInMethods') && data['signInMethods'] != null)
          ? List<String>.from(data['signInMethods'])
          : ['qr_code', 'manual_code'], // Default to regular methods
      signInSecurityTier: data['signInSecurityTier'] ?? 'regular',
      manualCode: data['manualCode'],
      hasLiveQuiz: data['hasLiveQuiz'] ?? false,
      liveQuizId: data['liveQuizId'],
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

  /// Returns the event end time based on selectedDateTime + eventDuration
  DateTime get eventEndTime =>
      selectedDateTime.add(Duration(hours: eventDuration));

  /// Returns the dwell tracking end time (event end + 1 hour buffer)
  DateTime get dwellTrackingEndTime =>
      eventEndTime.add(const Duration(hours: 1));

  /// Check if a user is a co-host of this event
  bool isCoHost(String userId) {
    return coHosts.contains(userId);
  }

  /// Check if a user has management permissions (creator or co-host)
  bool hasManagementPermissions(String userId) {
    return customerUid == userId || coHosts.contains(userId);
  }

  /// Check if a specific sign-in method is enabled
  bool isSignInMethodEnabled(String method) {
    // For new security tier system
    if (signInSecurityTier != null) {
      switch (signInSecurityTier) {
        case 'most_secure':
          // Most Secure: requires geofence AND facial recognition combo
          return method == 'geofence' || method == 'facial_recognition';
        case 'geofence_only':
          // Geofence Only: requires only geofence
          return method == 'geofence';
        case 'regular':
          // Regular: QR code or manual code
          return method == 'qr_code' || method == 'manual_code';
        case 'all':
          // All methods available
          return true;
        default:
          break;
      }
    }
    
    // Legacy support: check individual methods
    return signInMethods.contains(method);
  }
  
  /// Get available sign-in methods based on security tier
  List<String> getAvailableSignInMethods() {
    if (signInSecurityTier != null) {
      switch (signInSecurityTier) {
        case 'most_secure':
          return ['most_secure']; // Special indicator for geofence + facial combo
        case 'geofence_only':
          return ['geofence'];
        case 'regular':
          return ['qr_code', 'manual_code'];
        case 'all':
          return ['most_secure', 'qr_code', 'manual_code'];
        default:
          break;
      }
    }
    
    // Legacy support
    return signInMethods;
  }
  
  /// Check if the event requires geofence-based sign-in
  bool get requiresGeofence {
    return signInSecurityTier == 'most_secure' || 
           signInSecurityTier == 'geofence_only' ||
           signInSecurityTier == 'all' ||
           signInMethods.contains('geofence');
  }

  /// Get the manual code for the event (generates one if not set)
  String getManualCode() {
    if (manualCode != null && manualCode!.isNotEmpty) {
      return manualCode!;
    }
    // Generate a code based on event ID if not set
    return id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};

    data['id'] = id;
    data['groupName'] = groupName;
    data['title'] = title;
    data['description'] = description;
    data['location'] = location;
    if (locationName != null) data['locationName'] = locationName;
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
    data['ticketsEnabled'] = ticketsEnabled;
    data['maxTickets'] = maxTickets;
    data['issuedTickets'] = issuedTickets;
    if (ticketPrice != null) data['ticketPrice'] = ticketPrice;
    data['ticketUpgradeEnabled'] = ticketUpgradeEnabled;
    if (ticketUpgradePrice != null)
      data['ticketUpgradePrice'] = ticketUpgradePrice;
    data['eventDuration'] = eventDuration;
    data['coHosts'] = coHosts;
    if (organizationId != null) data['organizationId'] = organizationId;
    data['accessList'] = accessList;
    data['signInMethods'] = signInMethods;
    if (signInSecurityTier != null) data['signInSecurityTier'] = signInSecurityTier;
    if (manualCode != null) data['manualCode'] = manualCode;
    data['hasLiveQuiz'] = hasLiveQuiz;
    if (liveQuizId != null) data['liveQuizId'] = liveQuizId;
    return data;
  }
}
