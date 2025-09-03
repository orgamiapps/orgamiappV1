import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class CreatePhotoPostScreen extends StatefulWidget {
  final String organizationId;
  const CreatePhotoPostScreen({super.key, required this.organizationId});

  @override
  State<CreatePhotoPostScreen> createState() => _CreatePhotoPostScreenState();
}

class _CreatePhotoPostScreenState extends State<CreatePhotoPostScreen> {
  final _captionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<File> _selectedImages = [];
  bool _isPosting = false;
  bool _isMember = false;
  bool _checkingPermission = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkMemberPermission();
  }

  Future<void> _checkMemberPermission() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _checkingPermission = false);
      return;
    }

    try {
      // Check if user is a member of the group
      final memberDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      setState(() {
        _isMember = memberDoc.exists;
        _checkingPermission = false;
      });
    } catch (e) {
      setState(() => _checkingPermission = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFiles.isNotEmpty) {
        setState(() {
          // Limit to 10 images total
          final remainingSlots = 10 - _selectedImages.length;
          final filesToAdd = pickedFiles.take(remainingSlots);
          _selectedImages.addAll(filesToAdd.map((xFile) => File(xFile.path)));
        });

        if (pickedFiles.length > 10 - _selectedImages.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 10 photos allowed per post'),
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking images: $e')),
      );
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (photo != null && _selectedImages.length < 10) {
        setState(() {
          _selectedImages.add(File(photo.path));
        });
      } else if (_selectedImages.length >= 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum 10 photos allowed per post'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking photo: $e')),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<List<String>> _uploadImages() async {
    final List<String> imageUrls = [];
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String userId = FirebaseAuth.instance.currentUser!.uid;

    for (int i = 0; i < _selectedImages.length; i++) {
      final File image = _selectedImages[i];
      final String fileName = 'groups/${widget.organizationId}/photos/${userId}_${timestamp}_$i.jpg';
      
      try {
        final Reference ref = FirebaseStorage.instance.ref().child(fileName);
        final UploadTask uploadTask = ref.putFile(
          image,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        
        final TaskSnapshot snapshot = await uploadTask;
        final String downloadUrl = await snapshot.ref.getDownloadURL();
        imageUrls.add(downloadUrl);
      } catch (e) {
        throw Exception('Failed to upload image ${i + 1}: $e');
      }
    }

    return imageUrls;
  }

  Future<void> _postPhoto() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one photo')),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Upload images first
      final List<String> imageUrls = await _uploadImages();

      // Get user's role
      final memberDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      final String userRole = memberDoc.data()?['role'] ?? 'member';

      // Create photo post document
      await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .add({
            'type': 'photo',
            'caption': _captionController.text.trim(),
            'imageUrls': imageUrls,
            'authorId': user.uid,
            'authorName': user.displayName ?? 'Unknown',
            'authorEmail': user.email,
            'authorRole': userRole,
            'createdAt': FieldValue.serverTimestamp(),
            'likes': [],
            'comments': [],
            'isPinned': false,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo posted successfully!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting photo: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Share Photo'),
          backgroundColor: const Color(0xFF667EEA),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isMember) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Share Photo'),
          backgroundColor: const Color(0xFF667EEA),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Members Only',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'You need to be a member of this group to share photos',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Photo'),
        backgroundColor: const Color(0xFF667EEA),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: (_isPosting || _selectedImages.isEmpty) ? null : _postPhoto,
            child: _isPosting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Share',
                    style: TextStyle(
                      color: _selectedImages.isEmpty ? Colors.white54 : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Image selection area
                  if (_selectedImages.isEmpty) ...[
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Add Photos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Share up to 10 photos with your group',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _pickImages,
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Gallery'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF667EEA),
                                ),
                              ),
                              const SizedBox(width: 16),
                              OutlinedButton.icon(
                                onPressed: _takePhoto,
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Camera'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF667EEA),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Display selected images
                    SizedBox(
                      height: _selectedImages.length == 1 ? 400 : 300,
                      child: _selectedImages.length == 1
                          ? Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.file(
                                    _selectedImages[0],
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    onPressed: () => _removeImage(0),
                                    icon: const Icon(Icons.close),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedImages.length,
                              itemBuilder: (context, index) {
                                return Container(
                                  width: 200,
                                  margin: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.file(
                                          _selectedImages[index],
                                          width: double.infinity,
                                          height: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: IconButton(
                                          onPressed: () => _removeImage(index),
                                          icon: const Icon(Icons.close, size: 20),
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.black54,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.all(4),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedImages.length < 10)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: _pickImages,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: Text('Add More (${10 - _selectedImages.length} left)'),
                          ),
                          const SizedBox(width: 16),
                          TextButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                          ),
                        ],
                      ),
                  ],

                  const SizedBox(height: 24),

                  // Caption input
                  TextFormField(
                    controller: _captionController,
                    decoration: InputDecoration(
                      labelText: 'Caption (optional)',
                      hintText: 'Write a caption...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignLabelWithHint: true,
                      prefixIcon: const Icon(Icons.edit),
                    ),
                    maxLines: 3,
                    maxLength: 500,
                  ),

                  const SizedBox(height: 16),

                  // Info message
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your photos will be visible to all group members in the Feed.',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
