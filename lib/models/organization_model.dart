import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationModel {
  final String id;
  final String name;
  final String description;
  final String category;
  final String? logoUrl;
  final String? bannerUrl;
  final String defaultEventVisibility; // 'public' or 'private'
  final String createdBy;
  final DateTime createdAt;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;

  OrganizationModel({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.logoUrl,
    this.bannerUrl,
    required this.defaultEventVisibility,
    required this.createdBy,
    required this.createdAt,
    this.locationAddress,
    this.latitude,
    this.longitude,
  });

  factory OrganizationModel.fromJson(Map<String, dynamic> data) {
    return OrganizationModel(
      id: data['id'],
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? 'Other',
      logoUrl: data['logoUrl'],
      bannerUrl: data['bannerUrl'],
      defaultEventVisibility: data['defaultEventVisibility'] ?? 'public',
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      locationAddress: data['locationAddress'],
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'logoUrl': logoUrl,
      'bannerUrl': bannerUrl,
      'defaultEventVisibility': defaultEventVisibility,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'locationAddress': locationAddress,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
