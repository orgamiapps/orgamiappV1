import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Screens/Events/Widget/SingleEventListViewItem.dart';

class MyProfileScreen extends StatefulWidget {
  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  String? bio;
  bool isEditingBio = false;
  final TextEditingController _bioController = TextEditingController();
  List<EventModel> createdEvents = [];
  List<EventModel> attendedEvents = [];
  bool isLoading = true;
  int selectedTab = 1; // 1 = Created, 2 = Attended

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      isLoading = true;
    });
    // Fetch events created by user
    final created = await FirebaseFirestoreHelper()
        .getEventsCreatedByUser(CustomerController.logeInCustomer!.uid);
    // Fetch events attended by user
    final attended = await FirebaseFirestoreHelper()
        .getEventsAttendedByUser(CustomerController.logeInCustomer!.uid);
    setState(() {
      createdEvents = created;
      attendedEvents = attended;
      bio = CustomerController.logeInCustomer?.bio ?? '';
      _bioController.text = bio ?? '';
      isLoading = false;
    });
  }

  void _saveBio() async {
    setState(() {
      isEditingBio = false;
    });
    CustomerController.logeInCustomer?.bio = _bioController.text.trim();
    await FirebaseFirestoreHelper().updateCustomerProfile(
      customerId: CustomerController.logeInCustomer!.uid,
      name: CustomerController.logeInCustomer!.name,
      profilePictureUrl: CustomerController.logeInCustomer!.profilePictureUrl,
      bio: _bioController.text.trim(),
    );
    setState(() {
      bio = _bioController.text.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = CustomerController.logeInCustomer;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: AppThemeColor.darkGreenColor,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile Picture
                    GestureDetector(
                      onTap: () {/* TODO: Add image picker */},
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: user?.profilePictureUrl != null
                            ? NetworkImage(user!.profilePictureUrl!)
                            : null,
                        child: user?.profilePictureUrl == null
                            ? const Icon(Icons.person,
                                size: 50, color: Colors.grey)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.name ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: Dimensions.fontSizeExtraLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Biography
                    isEditingBio
                        ? Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bioController,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter your biography...',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.check),
                                onPressed: _saveBio,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  bio ?? '',
                                  style: const TextStyle(
                                    fontSize: Dimensions.fontSizeDefault,
                                    color: AppThemeColor.dullFontColor,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () {
                                  setState(() {
                                    isEditingBio = true;
                                  });
                                },
                              ),
                            ],
                          ),
                    const SizedBox(height: 24),
                    // Tab Bar
                    Row(
                      children: [
                        _singleTabBarView(label: 'Created Events', index: 1),
                        _singleTabBarView(label: 'Attended', index: 2),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Tab Content
                    selectedTab == 1
                        ? (createdEvents.isEmpty
                            ? const Text('No events created.')
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: createdEvents.length,
                                itemBuilder: (context, index) {
                                  return SingleEventListViewItem(
                                      eventModel: createdEvents[index]);
                                },
                              ))
                        : (attendedEvents.isEmpty
                            ? const Text('No events attended.')
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: attendedEvents.length,
                                itemBuilder: (context, index) {
                                  return SingleEventListViewItem(
                                      eventModel: attendedEvents[index]);
                                },
                              )),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _singleTabBarView({required String label, required int index}) {
    bool selectedOne = selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedTab = index;
          });
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selectedOne
                ? AppThemeColor.darkBlueColor
                : AppThemeColor.darkGreenColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: AppThemeColor.pureWhiteColor,
                fontSize: Dimensions.fontSizeDefault,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
