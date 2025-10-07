import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Script to update existing subscription prices from $20 to $5
/// Run this to update your existing subscription in Firestore
Future<void> main() async {
  // Initialize Firebase
  // Note: Make sure Firebase is properly configured before running this
  try {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;

    // Get current user ID
    final userId = auth.currentUser?.uid;
    if (userId == null) {
      print('Error: No user is currently logged in');
      return;
    }

    print('Updating subscription for user: $userId');

    // Get the current subscription
    final subscriptionDoc = await firestore
        .collection('subscriptions')
        .doc(userId)
        .get();

    if (!subscriptionDoc.exists) {
      print('No subscription found for this user');
      return;
    }

    final data = subscriptionDoc.data();
    final currentPrice = data?['priceAmount'] as int?;

    print(
      'Current price: $currentPrice cents (\$${(currentPrice ?? 0) / 100})',
    );

    if (currentPrice == 2000) {
      // Update from $20 to $5
      await firestore.collection('subscriptions').doc(userId).update({
        'priceAmount': 500, // $5.00 in cents
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Successfully updated subscription price from \$20.00 to \$5.00');
    } else if (currentPrice == 500) {
      print('✅ Subscription price is already set to \$5.00');
    } else {
      print('⚠️  Unexpected price amount: $currentPrice cents');
      print('Do you want to update it to \$5.00 (500 cents)? [y/n]');
      // Note: This is a simple script. For production, add proper input handling
    }
  } catch (e) {
    print('Error updating subscription: $e');
  }
}
