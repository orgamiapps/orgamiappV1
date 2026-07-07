import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/toast.dart';

class CoHostManagementWidget extends StatefulWidget {
  final EventModel eventModel;
  final VoidCallback? onCoHostsChanged;

  const CoHostManagementWidget({
    super.key,
    required this.eventModel,
    this.onCoHostsChanged,
  });

  @override
  State<CoHostManagementWidget> createState() => _CoHostManagementWidgetState();
}

class _CoHostManagementWidgetState extends State<CoHostManagementWidget> {
  List<CustomerModel> coHosts = [];
  bool isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCoHosts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCoHosts() async {
    setState(() {
      isLoading = true;
    });

    try {
      final coHostsList = await FirebaseFirestoreHelper().getCoHosts(
        eventId: widget.eventModel.id,
      );

      setState(() {
        coHosts = coHostsList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ShowToast().showNormalToast(msg: 'Error loading co-hosts: $e');
    }
  }

  void _showAddCoHostDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _AddCoHostDialog(
          eventId: widget.eventModel.id,
          existingCoHosts: coHosts,
          onCoHostAdded: () {
            _loadCoHosts();
            widget.onCoHostsChanged?.call();
          },
        );
      },
    );
  }

  Future<void> _removeCoHost(CustomerModel coHost) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppThemeColor.orangeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_remove,
                  color: AppThemeColor.orangeColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Remove Co-Host',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove ${coHost.name} as a co-host? They will lose all management permissions for this event.',
            style: const TextStyle(
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppThemeColor.dullFontColor,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeColor.orangeColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.white, fontFamily: 'Roboto'),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        isLoading = true;
      });

      try {
        final success = await FirebaseFirestoreHelper().removeCoHost(
          eventId: widget.eventModel.id,
          coHostUserId: coHost.uid,
        );

        if (success) {
          ShowToast().showNormalToast(msg: '${coHost.name} removed as co-host');
          _loadCoHosts();
          widget.onCoHostsChanged?.call();
        } else {
          ShowToast().showNormalToast(msg: 'Failed to remove co-host');
        }
      } catch (e) {
        ShowToast().showNormalToast(msg: 'Error removing co-host: $e');
      } finally {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.people,
                  color: AppThemeColor.darkBlueColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Co-Hosts',
                  style: TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              GestureDetector(
                onTap: _showAddCoHostDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppThemeColor.darkBlueColor,
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_add,
                        color: AppThemeColor.darkBlueColor,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Add Co-Host',
                        style: TextStyle(
                          color: AppThemeColor.darkBlueColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            'Co-hosts have shared management permissions including editing the event, viewing analytics, and adding questions.',
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: 14,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Co-hosts list
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: AppThemeColor.darkBlueColor,
              ),
            )
          else if (coHosts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppThemeColor.lightBlueColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline,
                    color: AppThemeColor.dullFontColor,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Co-Hosts',
                    style: TextStyle(
                      color: AppThemeColor.dullFontColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add co-hosts to share event management',
                    style: TextStyle(
                      color: AppThemeColor.dullFontColor.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: coHosts.map((coHost) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppThemeColor.lightBlueColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppThemeColor.lightBlueColor.withValues(
                        alpha: 0.2,
                      ),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppThemeColor.darkBlueColor.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            coHost.name.isNotEmpty
                                ? coHost.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppThemeColor.darkBlueColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // User info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              coHost.name,
                              style: const TextStyle(
                                color: AppThemeColor.pureBlackColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            if (coHost.username != null &&
                                coHost.username!.isNotEmpty)
                              Text(
                                '@${coHost.username}',
                                style: TextStyle(
                                  color: AppThemeColor.dullFontColor,
                                  fontSize: 14,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Remove button
                      GestureDetector(
                        onTap: () => _removeCoHost(coHost),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppThemeColor.orangeColor.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.remove,
                            color: AppThemeColor.orangeColor,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _AddCoHostDialog extends StatefulWidget {
  final String eventId;
  final List<CustomerModel> existingCoHosts;
  final VoidCallback onCoHostAdded;

  const _AddCoHostDialog({
    required this.eventId,
    required this.existingCoHosts,
    required this.onCoHostAdded,
  });

  @override
  State<_AddCoHostDialog> createState() => _AddCoHostDialogState();
}

class _AddCoHostDialogState extends State<_AddCoHostDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<CustomerModel> searchResults = [];
  bool isSearching = false;
  bool isAddingCoHost = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchController.text.length >= 2) {
      _performSearch();
    } else {
      setState(() {
        searchResults.clear();
      });
    }
  }

  Future<void> _performSearch() async {
    setState(() {
      isSearching = true;
    });

    try {
      final results = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: _searchController.text,
        limit: 20,
      );

      // Filter out existing co-hosts and the current user
      final filteredResults = results.where((user) {
        return !widget.existingCoHosts.any((coHost) => coHost.uid == user.uid);
      }).toList();

      setState(() {
        searchResults = filteredResults;
        isSearching = false;
      });
    } catch (e) {
      setState(() {
        isSearching = false;
      });
      ShowToast().showNormalToast(msg: 'Error searching users: $e');
    }
  }

  Future<void> _addCoHost(CustomerModel user) async {
    setState(() {
      isAddingCoHost = true;
    });

    try {
      final success = await FirebaseFirestoreHelper().addCoHost(
        eventId: widget.eventId,
        coHostUserId: user.uid,
      );

      if (success) {
        ShowToast().showNormalToast(msg: '${user.name} added as co-host');
        widget.onCoHostAdded();
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        ShowToast().showNormalToast(msg: 'Failed to add co-host');
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Error adding co-host: $e');
    } finally {
      setState(() {
        isAddingCoHost = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_add,
                    color: AppThemeColor.darkBlueColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Add Co-Host',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: AppThemeColor.dullFontColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by name or username...',
                hintStyle: TextStyle(
                  color: AppThemeColor.dullFontColor.withValues(alpha: 0.6),
                  fontFamily: 'Roboto',
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppThemeColor.dullFontColor,
                ),
                filled: true,
                fillColor: AppThemeColor.lightBlueColor.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppThemeColor.borderColor,
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppThemeColor.borderColor,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppThemeColor.darkBlueColor,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Search results
            Expanded(
              child: isSearching
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppThemeColor.darkBlueColor,
                      ),
                    )
                  : searchResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search,
                            color: AppThemeColor.dullFontColor.withValues(
                              alpha: 0.5,
                            ),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _searchController.text.isEmpty
                                ? 'Start typing to search users'
                                : 'No users found',
                            style: TextStyle(
                              color: AppThemeColor.dullFontColor.withValues(
                                alpha: 0.7,
                              ),
                              fontSize: 16,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final user = searchResults[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppThemeColor.darkBlueColor.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  user.name.isNotEmpty
                                      ? user.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: AppThemeColor.darkBlueColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              user.name,
                              style: const TextStyle(
                                color: AppThemeColor.pureBlackColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            subtitle:
                                user.username != null &&
                                    user.username!.isNotEmpty
                                ? Text(
                                    '@${user.username}',
                                    style: TextStyle(
                                      color: AppThemeColor.dullFontColor,
                                      fontSize: 14,
                                      fontFamily: 'Roboto',
                                    ),
                                  )
                                : null,
                            trailing: isAddingCoHost
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppThemeColor.darkBlueColor,
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: () => _addCoHost(user),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          AppThemeColor.darkBlueColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'Add',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
