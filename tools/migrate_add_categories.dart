import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../lib/Utils/firebase_options.dart';

Future<void> main() async {
  // Initialize Firebase with options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;
  final eventsCollection = firestore.collection('Events');

  final snapshot = await eventsCollection.get();

  int updatedCount = 0;

  for (final doc in snapshot.docs) {
    final data = doc.data();
    if (!data.containsKey('categories')) {
      await doc.reference.update({'categories': []});
      updatedCount++;
      print('Updated document:  [32m${doc.id} [0m');
    }
  }

  print('Migration complete. Updated $updatedCount documents.');
}
