import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/organization_model.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/firebase/firebase_storage_helper.dart';
import 'dart:io';

class EditGroupDetailsScreen extends StatefulWidget {
  final String organizationId;
  final OrganizationModel organization;

  const EditGroupDetailsScreen({
    super.key,
    required this.organizationId,
    required this.organization,
  });

  @override
  State<EditGroupDetailsScreen> createState() => _EditGroupDetailsScreenState();
}

class _EditGroupDetailsScreenState extends State<EditGroupDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();

  String _selectedCategory = 'Other';
  String _selectedEventVisibility = 'public';
  String _selectedAnnouncementVisibility = 'public';
  String _selectedPollVisibility = 'public';
  String _selectedPhotoVisibility = 'public';
  bool _isLoading = false;
  bool _hasChanges = false;

  // Image management
  File? _logoFile;
  File? _bannerFile;
  String? _currentLogoUrl;
  String? _currentBannerUrl;

  final OrganizationHelper _orgHelper = OrganizationHelper();

  final List<String> _categories = [
    'Business',
    'Club',
    'School',
    'Sports',
    'Other',
  ];

  final List<Map<String, String>> _visibilityOptions = [
    {
      'value': 'public',
      'label': 'Public',
      'description': 'Visible to everyone',
    },
    {
      'value': 'private',
      'label': 'Members Only',
      'description': 'Visible to members only',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    _nameController.text = widget.organization.name;
    _descriptionController.text = widget.organization.description;
    _selectedCategory = widget.organization.category;
    _selectedEventVisibility = widget.organization.defaultEventVisibility;

    // Initialize other visibility settings to same as events for consistency
    _selectedAnnouncementVisibility =
        widget.organization.defaultEventVisibility;
    _selectedPollVisibility = widget.organization.defaultEventVisibility;
    _selectedPhotoVisibility = widget.organization.defaultEventVisibility;

    // Add listeners to track changes
    _nameController.addListener(_onFieldChanged);
    _descriptionController.addListener(_onFieldChanged);
    _websiteController.addListener(_onFieldChanged);

    // Load website if available
    _loadAdditionalData();
  }

  Future<void> _loadAdditionalData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final website = data['website']?.toString() ?? '';
        final logoUrl = data['logoUrl']?.toString();
        final bannerUrl = data['bannerUrl']?.toString();

        // Load visibility settings or use defaults
        final announcementVisibility =
            data['defaultAnnouncementVisibility']?.toString() ??
            _selectedEventVisibility;
        final pollVisibility =
            data['defaultPollVisibility']?.toString() ??
            _selectedEventVisibility;
        final photoVisibility =
            data['defaultPhotoVisibility']?.toString() ??
            _selectedEventVisibility;

        setState(() {
          _websiteController.text = website;
          _currentLogoUrl = logoUrl;
          _currentBannerUrl = bannerUrl;
          _selectedAnnouncementVisibility = announcementVisibility;
          _selectedPollVisibility = pollVisibility;
          _selectedPhotoVisibility = photoVisibility;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  void _onFieldChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  void _onImageChanged() {
    _onFieldChanged();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Upload images if they have been changed
      String? logoUrl = _currentLogoUrl;
      String? bannerUrl = _currentBannerUrl;

      if (_logoFile != null) {
        logoUrl = await FirebaseStorageHelper.uploadOrganizationImage(
          organizationId: widget.organizationId,
          imageFile: _logoFile!,
          isBanner: false,
        );
      }

      if (_bannerFile != null) {
        bannerUrl = await FirebaseStorageHelper.uploadOrganizationImage(
          organizationId: widget.organizationId,
          imageFile: _bannerFile!,
          isBanner: true,
        );
      }

      // Prepare update data
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'name_lowercase': _nameController.text.trim().toLowerCase(),
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'category_lowercase': _selectedCategory.toLowerCase(),
        'defaultEventVisibility': _selectedEventVisibility,
        'defaultAnnouncementVisibility': _selectedAnnouncementVisibility,
        'defaultPollVisibility': _selectedPollVisibility,
        'defaultPhotoVisibility': _selectedPhotoVisibility,
        'website': _websiteController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      };

      // Add image URLs if they exist
      if (logoUrl != null) {
        updateData['logoUrl'] = logoUrl;
      }
      if (bannerUrl != null) {
        updateData['bannerUrl'] = bannerUrl;
      }

      final ok = await _orgHelper.updateOrganizationDetailsUnique(
        widget.organizationId,
        updateData,
      );
      if (!ok) throw Exception('Failed to save changes (name may be taken)');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group details updated successfully!'),
            backgroundColor: Color(0xFF667EEA),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Group Details',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic Information Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: const Color(0xFF667EEA),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Basic Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Group Name
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Group Name *',
                        hintText: 'Enter group name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.group),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Group name is required';
                        }
                        if (value.trim().length < 3) {
                          return 'Group name must be at least 3 characters';
                        }
                        return null;
                      },
                      maxLength: 50,
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        hintText: 'Describe your group...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.description),
                      ),
                      maxLines: 4,
                      maxLength: 500,
                      validator: (value) {
                        if (value != null && value.length > 500) {
                          return 'Description must be less than 500 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Category Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.category),
                      ),
                      items: _categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedCategory = value;
                            _onFieldChanged();
                          });
                        }
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Image Management Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.image, color: const Color(0xFF667EEA)),
                        const SizedBox(width: 8),
                        const Text(
                          'Group Images',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Logo
                    _ImagePickerTile(
                      label: 'Logo',
                      hint: 'Recommended 512x512 PNG',
                      file: _logoFile,
                      currentImageUrl: _currentLogoUrl,
                      onPick: () async {
                        final f =
                            await FirebaseStorageHelper.pickImageFromGallery();
                        if (f != null) {
                          setState(() => _logoFile = f);
                          _onImageChanged();
                        }
                      },
                      onClear: () {
                        setState(() {
                          _logoFile = null;
                          _currentLogoUrl = null;
                        });
                        _onImageChanged();
                      },
                    ),
                    const SizedBox(height: 12),

                    // Banner
                    _ImagePickerTile(
                      label: 'Banner',
                      hint: 'Recommended 1600x600 JPG',
                      file: _bannerFile,
                      currentImageUrl: _currentBannerUrl,
                      onPick: () async {
                        final f =
                            await FirebaseStorageHelper.pickImageFromGallery();
                        if (f != null) {
                          setState(() => _bannerFile = f);
                          _onImageChanged();
                        }
                      },
                      onClear: () {
                        setState(() {
                          _bannerFile = null;
                          _currentBannerUrl = null;
                        });
                        _onImageChanged();
                      },
                      isBanner: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Contact Information Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.contact_page,
                          color: const Color(0xFF667EEA),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Contact Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Website
                    TextFormField(
                      controller: _websiteController,
                      decoration: InputDecoration(
                        labelText: 'Website',
                        hintText: 'https://example.com',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.language),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final uri = Uri.tryParse(value);
                          if (uri == null || !uri.hasScheme) {
                            return 'Please enter a valid URL (e.g., https://example.com)';
                          }
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Group Settings Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings, color: const Color(0xFF667EEA)),
                        const SizedBox(width: 8),
                        const Text(
                          'Group Settings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Configure default visibility settings for different types of content in your group.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    // Events Visibility
                    _buildVisibilitySection(
                      title: 'Events',
                      icon: Icons.event,
                      description: 'Who can see events created in this group',
                      selectedValue: _selectedEventVisibility,
                      onChanged: (value) {
                        setState(() {
                          _selectedEventVisibility = value;
                          _onFieldChanged();
                        });
                      },
                    ),

                    const SizedBox(height: 20),

                    // Announcements Visibility
                    _buildVisibilitySection(
                      title: 'Announcements',
                      icon: Icons.campaign,
                      description:
                          'Who can see announcements posted in this group',
                      selectedValue: _selectedAnnouncementVisibility,
                      onChanged: (value) {
                        setState(() {
                          _selectedAnnouncementVisibility = value;
                          _onFieldChanged();
                        });
                      },
                    ),

                    const SizedBox(height: 20),

                    // Polls Visibility
                    _buildVisibilitySection(
                      title: 'Polls',
                      icon: Icons.poll,
                      description: 'Who can see polls created in this group',
                      selectedValue: _selectedPollVisibility,
                      onChanged: (value) {
                        setState(() {
                          _selectedPollVisibility = value;
                          _onFieldChanged();
                        });
                      },
                    ),

                    const SizedBox(height: 20),

                    // Photos Visibility
                    _buildVisibilitySection(
                      title: 'Photos',
                      icon: Icons.photo_library,
                      description: 'Who can see photos shared in this group',
                      selectedValue: _selectedPhotoVisibility,
                      onChanged: (value) {
                        setState(() {
                          _selectedPhotoVisibility = value;
                          _onFieldChanged();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Save Button (for mobile convenience)
            if (_hasChanges)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Saving...'),
                          ],
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilitySection({
    required String title,
    required IconData icon,
    required String description,
    required String selectedValue,
    required Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF667EEA)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < _visibilityOptions.length; i++) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(_visibilityOptions[i]['value']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: selectedValue == _visibilityOptions[i]['value']
                            ? const Color(0xFF667EEA)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selectedValue == _visibilityOptions[i]['value']
                              ? const Color(0xFF667EEA)
                              : Colors.grey[300]!,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _visibilityOptions[i]['value'] == 'public'
                                ? Icons.public
                                : Icons.group,
                            color:
                                selectedValue == _visibilityOptions[i]['value']
                                ? Colors.white
                                : Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _visibilityOptions[i]['label']!,
                            style: TextStyle(
                              color:
                                  selectedValue ==
                                      _visibilityOptions[i]['value']
                                  ? Colors.white
                                  : Colors.grey[800],
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (i < _visibilityOptions.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  final String label;
  final String hint;
  final File? file;
  final String? currentImageUrl;
  final VoidCallback onClear;
  final VoidCallback onPick;
  final bool isBanner;

  const _ImagePickerTile({
    required this.label,
    required this.hint,
    required this.file,
    this.currentImageUrl,
    required this.onPick,
    required this.onClear,
    this.isBanner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (file != null || currentImageUrl != null)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: isBanner ? 120 : 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF8FAFC),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              alignment: Alignment.center,
              child: _buildImageContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent() {
    if (file != null) {
      // Show selected file
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file!,
          width: double.infinity,
          height: isBanner ? 120 : 100,
          fit: BoxFit.cover,
        ),
      );
    } else if (currentImageUrl != null && currentImageUrl!.isNotEmpty) {
      // Show current image from URL
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          currentImageUrl!,
          width: double.infinity,
          height: isBanner ? 120 : 100,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder();
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
        ),
      );
    } else {
      // Show placeholder
      return _buildPlaceholder();
    }
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF6B7280)),
        SizedBox(height: 6),
        Text('Tap to select image'),
      ],
    );
  }
}
