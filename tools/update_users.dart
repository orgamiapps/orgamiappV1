import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  print('Starting user database update...');
  
  try {
    final firestore = FirebaseFirestore.instance;
    final querySnapshot = await firestore.collection('Customers').get();
    
    print('Found ${querySnapshot.docs.length} users to update');
    
    int updatedCount = 0;
    
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      Map<String, dynamic> updates = {};
      
      // Check if isDiscoverable field exists
      if (!data.containsKey('isDiscoverable')) {
        updates['isDiscoverable'] = true;
      }
      
      // Check if username field exists
      if (!data.containsKey('username') || data['username'] == null) {
        // Generate username from name
        String name = data['name'] ?? 'User';
        String baseUsername = name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '')
            .trim();
        
        if (baseUsername.isEmpty) {
          baseUsername = 'user';
        }
        
        // Add timestamp to ensure uniqueness
        String username = '${baseUsername}${DateTime.now().millisecondsSinceEpoch}';
        updates['username'] = username;
      }
      
      // Update if there are any missing fields
      if (updates.isNotEmpty) {
        await doc.reference.update(updates);
        updatedCount++;
        print('Updated user ${doc.id} with: $updates');
      }
    }
    
    print('Successfully updated $updatedCount users');
  } catch (e) {
    print('Error updating users: $e');
  }
  
  print('User database update completed');
} 