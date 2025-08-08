import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/models/event_model.dart';

class TestConnectivityScreen extends StatefulWidget {
  const TestConnectivityScreen({super.key});

  @override
  State<TestConnectivityScreen> createState() => _TestConnectivityScreenState();
}

class _TestConnectivityScreenState extends State<TestConnectivityScreen> {
  String status = 'Testing...';
  String details = '';

  @override
  void initState() {
    super.initState();
    testFirebaseConnectivity();
  }

  Future<void> testFirebaseConnectivity() async {
    try {
      setState(() {
        status = 'Testing Firestore connection...';
        details = '';
      });

      // Test basic connection
      final instance = FirebaseFirestore.instance;
      setState(() {
        details += 'Firestore instance created\n';
      });

      // Test collection access
      final collection = instance.collection(EventModel.firebaseKey);
      setState(() {
        details += 'Collection "${EventModel.firebaseKey}" accessed\n';
      });

      // Test simple query
      final querySnapshot = await collection.limit(1).get();
      setState(() {
        details += 'Query executed successfully\n';
        details += 'Documents found: ${querySnapshot.docs.length}\n';
      });

      if (querySnapshot.docs.isEmpty) {
        setState(() {
          status = '✅ Connected - No Data';
          details += '\nFirestore is working but collection is empty.\n';
          details += 'Try creating an event first.';
        });
      } else {
        setState(() {
          status = '✅ Connected - Data Found';
          details += '\nFirestore is working with data!\n';
          details += 'Document ID: ${querySnapshot.docs.first.id}';
        });
      }

    } catch (e) {
      setState(() {
        status = '❌ Connection Failed';
        details = 'Error: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firestore Test'),
        backgroundColor: const Color(0xFF667EEA),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Status:',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(
                fontSize: 16,
                color: status.startsWith('✅') ? Colors.green : 
                       status.startsWith('❌') ? Colors.red : Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Details:',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    details.isEmpty ? 'Running tests...' : details,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: testFirebaseConnectivity,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Test Again'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[600],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Back'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
