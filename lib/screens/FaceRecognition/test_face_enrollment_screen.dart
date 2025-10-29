import 'package:flutter/material.dart';
import '../../models/event_model.dart';
import 'simple_face_enrollment_screen.dart';
import 'picture_face_enrollment_screen.dart';

/// Test screen to easily test face enrollment in different modes
class TestFaceEnrollmentScreen extends StatelessWidget {
  const TestFaceEnrollmentScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Create a dummy event for testing
    final testEvent = EventModel(
      id: 'test_event_123',
      groupName: 'Test Group',
      title: 'Test Event for Face Enrollment',
      description: 'Testing facial recognition enrollment',
      location: 'Test Location',
      customerUid: 'test_customer',
      imageUrl: '',
      selectedDateTime: DateTime.now().add(Duration(hours: 2)),
      eventGenerateTime: DateTime.now(),
      status: 'active',
      private: false,
      getLocation: true,
      radius: 10.0,
      latitude: 0.0,
      longitude: 0.0,
      signInMethods: ['facial_recognition', 'geofence'],
    );

    return Scaffold(
      appBar: AppBar(title: Text('Face Enrollment Test'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.face,
                size: 100,
                color: Theme.of(context).primaryColor,
              ),
              SizedBox(height: 40),
              Text(
                'Test Face Enrollment',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              Text(
                'Choose a mode to test the face enrollment:',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40),

              // Picture Mode Button (RECOMMENDED - WORKS!)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PictureFaceEnrollmentScreen(eventModel: testEvent),
                    ),
                  );
                },
                icon: Icon(Icons.photo_camera, size: 30),
                label: Text('PICTURE MODE ✅ WORKS!'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  textStyle: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Real Mode Button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SimpleFaceEnrollmentScreen(
                        eventModel: testEvent,
                        simulationMode: false, // Real mode
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.camera_alt),
                label: Text('TEST REAL MODE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Simulation Mode Button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SimpleFaceEnrollmentScreen(
                        eventModel: testEvent,
                        simulationMode: true, // Simulation mode
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.developer_mode),
                label: Text('TEST SIMULATION MODE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Guest Mode Test
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SimpleFaceEnrollmentScreen(
                        eventModel: testEvent,
                        guestUserId: 'guest_test_123',
                        guestUserName: 'Test Guest User',
                        simulationMode: true, // Use simulation for guest test
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.person_outline),
                label: Text('TEST GUEST MODE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              SizedBox(height: 40),

              // Info Card
              Card(
                color: Colors.grey[100],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 10),
                          Text(
                            'Debug Panel',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        'The debug panel shows real-time status including:\n'
                        '• Current state machine state\n'
                        '• Frame counter and processing stats\n'
                        '• Face detection results\n'
                        '• Error messages\n'
                        '• Elapsed time',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
