import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orgami/Screens/Home/HomeScreen.dart';
import 'package:orgami/Screens/Home/AccountScreen.dart';
import 'package:orgami/Screens/Home/NotificationsScreen.dart';
import 'package:orgami/Screens/Messaging/MessagingScreen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  int _selectedIndex = 0;

  final List<Widget> _dashBoardScreens = [
    const HomeScreen(),
    const MessagingScreen(),
    const NotificationsScreen(),
    const AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _bodyView()),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() {
          _selectedIndex = index;
        }),
        selectedItemColor: const Color(0xFF667EEA),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event, size: 20), label: ''),
          BottomNavigationBarItem(
            icon: Icon(Icons.message, size: 20),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications, size: 20),
            label: '',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.menu, size: 20), label: ''),
        ],
      ),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      height: _screenHeight,
      width: _screenWidth,
      child: Column(
        children: [Expanded(child: _dashBoardScreens[_selectedIndex])],
      ),
    );
  }
}
