import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart'
    show WidgetsFlutterBinding; // Needed for Firebase on Flutter
import 'package:orgami/firebase_options.dart';

Future<void> main() async {
  // Ensure Flutter bindings are initialized for Firebase plugins
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;
  final eventsCollection = firestore.collection('Events');

  final snapshot = await eventsCollection.get();

  // Use batched writes for efficiency and to avoid rate limits
  WriteBatch batch = firestore.batch();
  int pending = 0;

  for (final doc in snapshot.docs) {
    final data = doc.data();
    if (!data.containsKey('categories')) {
      batch.update(doc.reference, {'categories': <String>[]});
      pending++;

      // Commit every 400 updates to stay well under the 500 limit
      if (pending >= 400) {
        await batch.commit();
        batch = firestore.batch();
        pending = 0;
      }
    }
  }

  if (pending > 0) {
    await batch.commit();
  }
}
