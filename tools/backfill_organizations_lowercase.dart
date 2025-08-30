import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:attendus/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;
  final orgs = firestore.collection('Organizations');

  final snap = await orgs.get();
  WriteBatch batch = firestore.batch();
  int pending = 0;

  for (final doc in snap.docs) {
    final data = doc.data();
    final String name = (data['name'] ?? '').toString();
    final String category = (data['category'] ?? 'Other').toString();
    final updates = <String, dynamic>{
      'name_lowercase': name.toLowerCase(),
      'category_lowercase': category.toLowerCase(),
    };
    batch.update(doc.reference, updates);
    pending++;

    if (pending >= 400) {
      await batch.commit();
      batch = firestore.batch();
      pending = 0;
    }
  }

  if (pending > 0) {
    await batch.commit();
  }
}
