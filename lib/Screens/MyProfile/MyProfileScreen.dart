import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Screens/Events/Widget/SingleEventListViewItem.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';

class MyProfileScreen extends StatefulWidget {
  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with TickerProviderStateMixin {
  String? bio;
  bool isEditingBio = false;
  final TextEditingController _bioController = TextEditingController();
  List<EventModel> createdEvents = [];
  List<EventModel> attendedEvents = [];
  bool isLoading = true;
  int selectedTab = 1; // 1 = Created, 2 = Attended

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadProfileData();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Check if user is logged in
      if (CustomerController.logeInCustomer == null) {
        print('User not logged in');
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Please log in to view your profile');
        return;
      }

      print(
          'Loading profile data for user: ${CustomerController.logeInCustomer!.uid}');

      // Fetch events created by user
      final created = await FirebaseFirestoreHelper()
          .getEventsCreatedByUser(CustomerController.logeInCustomer!.uid);
      print('Created events count: ${created.length}');

      // Fetch events attended by user
      final attended = await FirebaseFirestoreHelper()
          .getEventsAttendedByUser(CustomerController.logeInCustomer!.uid);
      print('Attended events count: ${attended.length}');

      if (mounted) {
        setState(() {
          createdEvents = created;
          attendedEvents = attended;
          bio = CustomerController.logeInCustomer?.bio ?? '';
          _bioController.text = bio ?? '';
          isLoading = false;
        });
        print('Profile data loaded successfully');
      }
    } catch (e) {
      print('Error loading profile data: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(
            msg: 'Failed to load profile data: ${e.toString()}');
      }
    }
  }

  void _saveBio() async {
    if (_bioController.text.trim().isEmpty) {
      ShowToast().showNormalToast(msg: 'Bio cannot be empty');
      return;
    }

    setState(() {
      isEditingBio = false;
    });

    try {
      CustomerController.logeInCustomer?.bio = _bioController.text.trim();
      await FirebaseFirestoreHelper().updateCustomerProfile(
        customerId: CustomerController.logeInCustomer!.uid,
        name: CustomerController.logeInCustomer!.name,
        profilePictureUrl: CustomerController.logeInCustomer!.profilePictureUrl,
        bio: _bioController.text.trim(),
      );

      if (mounted) {
        setState(() {
          bio = _bioController.text.trim();
        });
        ShowToast().showNormalToast(msg: 'Bio updated successfully!');
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to update bio');
    }
  }

  void _cancelBioEdit() {
    setState(() {
      isEditingBio = false;
      _bioController.text = bio ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = CustomerController.logeInCustomer;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: isLoading
            ? _buildLoadingState()
            : FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: _buildProfileContent(user),
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildShimmerProfileHeader(),
          const SizedBox(height: 24),
          _buildShimmerTabs(),
          const SizedBox(height: 16),
          _buildShimmerEventList(),
        ],
      ),
    );
  }

  Widget _buildShimmerProfileHeader() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 200,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 300,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerTabs() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerEventList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: List.generate(
              3,
              (index) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  )),
        ),
      ),
    );
  }

  Widget _buildProfileContent(user) {
    return RefreshIndicator(
      onRefresh: _loadProfileData,
      color: const Color(0xFF667EEA),
      child: CustomScrollView(
        slivers: [
          // Back Button and Profile Header
          SliverToBoxAdapter(
            child: _buildProfileHeader(user),
          ),
          // Bio Section
          SliverToBoxAdapter(
            child: _buildBioSection(),
          ),
          // Stats Section
          SliverToBoxAdapter(
            child: _buildStatsSection(),
          ),
          // Tab Bar
          SliverToBoxAdapter(
            child: _buildTabBar(),
          ),
          // Tab Content
          SliverToBoxAdapter(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(user) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF667EEA),
            Color(0xFF764BA2),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          // Back Button and Header Row
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'My Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  fontFamily: 'Roboto',
                ),
              ),
              const Spacer(),
              // Empty container for balance
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 24),

          // Profile Picture Section
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: user?.profilePictureUrl != null
                        ? Image.network(
                            user!.profilePictureUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildDefaultProfilePicture();
                            },
                          )
                        : _buildDefaultProfilePicture(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Color(0xFF667EEA),
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // User Name
          Text(
            'Hi ${user?.name ?? 'User'}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 24,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome to your profile',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w400,
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultProfilePicture() {
    return Container(
      color: const Color(0xFFE1E5E9),
      child: const Icon(
        Icons.person,
        size: 60,
        color: Color(0xFF9CA3AF),
      ),
    );
  }

  Widget _buildBioSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    color: const Color(0xFF667EEA),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'About Me',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
              if (!isEditingBio)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      isEditingBio = true;
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Color(0xFF667EEA),
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          isEditingBio
              ? Column(
                  children: [
                    TextField(
                      controller: _bioController,
                      maxLines: 3,
                      maxLength: 150,
                      decoration: InputDecoration(
                        hintText: 'Tell us about yourself...',
                        hintStyle: TextStyle(
                          color: const Color(0xFF9CA3AF),
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: const Color(0xFFE1E5E9),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF667EEA),
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _cancelBioEdit,
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: const Color(0xFF9CA3AF),
                              fontSize: 14,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _saveBio,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667EEA),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Text(
                  bio?.isNotEmpty == true
                      ? bio!
                      : 'No bio added yet. Tap the edit button to add one!',
                  style: TextStyle(
                    fontSize: 14,
                    color: bio?.isNotEmpty == true
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFF9CA3AF),
                    fontStyle: bio?.isNotEmpty == true
                        ? FontStyle.normal
                        : FontStyle.italic,
                    fontFamily: 'Roboto',
                    height: 1.5,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics,
                color: const Color(0xFF667EEA),
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'My Activity',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.add_circle_outline,
                  value: createdEvents.length.toString(),
                  label: 'Created',
                  color: const Color(0xFF667EEA),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: const Color(0xFFE1E5E9),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.check_circle_outline,
                  value: attendedEvents.length.toString(),
                  label: 'Attended',
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: Color(0xFF1A1A1A),
            fontFamily: 'Roboto',
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: const Color(0xFF9CA3AF),
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildTabButton(
            label: 'Created Events',
            index: 1,
            icon: Icons.add_circle_outline,
          ),
          Container(
            width: 1,
            height: 40,
            color: const Color(0xFFE1E5E9),
          ),
          _buildTabButton(
            label: 'Attended',
            index: 2,
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required int index,
    required IconData icon,
  }) {
    bool isSelected = selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedTab = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF667EEA) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    final events = selectedTab == 1 ? createdEvents : attendedEvents;
    final emptyMessage = selectedTab == 1
        ? 'You haven\'t created any events yet'
        : 'You haven\'t attended any events yet';
    final emptyIcon = selectedTab == 1
        ? FontAwesomeIcons.plus
        : FontAwesomeIcons.calendarCheck;

    print('Building tab content - Selected tab: $selectedTab');
    print('Created events: ${createdEvents.length}');
    print('Attended events: ${attendedEvents.length}');
    print('Current events to show: ${events.length}');

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: events.isEmpty
          ? _buildEmptyState(emptyMessage, emptyIcon)
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              itemBuilder: (context, index) {
                print('Building event item at index: $index');
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: SingleEventListViewItem(
                    eventModel: events[index],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 64,
            color: const Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            selectedTab == 1
                ? 'Start creating amazing events!'
                : 'Join events to see them here',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadProfileData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
