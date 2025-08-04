import 'package:flashy_tab_bar2/flashy_tab_bar2.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orgami/Screens/Home/HomeScreen.dart';
import 'package:orgami/Screens/Home/SearchEventsScreen.dart';
import 'package:orgami/Screens/Home/SettingsScreen.dart';
import 'package:orgami/Screens/Home/NotificationsScreen.dart';
import 'package:orgami/Screens/QRScanner/QrScannerScreen.dart';

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
    const SearchEventsScreen(),
    QRScannerScreen(),
    const NotificationsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _bodyView()),
      bottomNavigationBar: FlashyTabBar(
        selectedIndex: _selectedIndex,
        showElevation: true,
        onItemSelected: (index) => setState(() {
          _selectedIndex = index;
        }),
        items: [
          _singleBottomBarItemView(iconData: Icons.event, title: 'Events'),
          _singleBottomBarItemView(iconData: Icons.search, title: 'Search'),
          _singleBottomBarItemView(
            iconData: FontAwesomeIcons.qrcode,
            title: 'Sign In',
          ),
          _singleBottomBarItemView(
            iconData: Icons.notifications,
            title: 'Alerts',
          ),
          _singleBottomBarItemView(iconData: Icons.settings, title: 'Settings'),
        ],
      ),
    );
  }

  FlashyTabBarItem _singleBottomBarItemView({
    required IconData iconData,
    required String title,
  }) {
    return FlashyTabBarItem(icon: Icon(iconData), title: Text(title));
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
