import 'package:flutter/material.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase/firebase_storage_helper.dart';
import 'package:flutter/services.dart';
import 'package:attendus/Services/creation_limit_service.dart';
import 'package:attendus/widgets/limit_reached_dialog.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtlr = TextEditingController();
  final _descCtlr = TextEditingController();
  String _category = 'Business';
  bool _submitting = false;
  File? _logoFile;
  File? _bannerFile;

  final _helper = OrganizationHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Group Details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtlr,
                decoration: const InputDecoration(
                  labelText: 'Group Name*',
                  helperText: 'Make it clear and recognizable',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtlr,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  helperText: 'What is this group about? (optional)',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: const [
                  DropdownMenuItem(value: 'Business', child: Text('Business')),
                  DropdownMenuItem(value: 'Club', child: Text('Club')),
                  DropdownMenuItem(value: 'School', child: Text('School')),
                  DropdownMenuItem(value: 'Sports', child: Text('Sports')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'Business'),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 24),
              const Text(
                'Branding (optional)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _ImagePickerTile(
                label: 'Logo (square)',
                hint: 'Recommended 512x512 PNG',
                file: _logoFile,
                onPick: () async {
                  final f = await FirebaseStorageHelper.pickImageFromGallery();
                  if (f != null) setState(() => _logoFile = f);
                },
                onClear: () => setState(() => _logoFile = null),
              ),
              const SizedBox(height: 12),
              _ImagePickerTile(
                label: 'Banner (wide)',
                hint: 'Recommended 1600x600 JPG',
                file: _bannerFile,
                onPick: () async {
                  final f = await FirebaseStorageHelper.pickImageFromGallery();
                  if (f != null) setState(() => _bannerFile = f);
                },
                onClear: () => setState(() => _bannerFile = null),
                isBanner: true,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;

                        // Check creation limit
                        final limitService = CreationLimitService();
                        if (!limitService.canCreateGroup) {
                          await LimitReachedDialog.show(
                            context,
                            type: 'group',
                            limit: CreationLimitService.FREE_GROUP_LIMIT,
                          );
                          return;
                        }

                        setState(() => _submitting = true);
                        final id = await _helper.createOrganization(
                          name: _nameCtlr.text.trim(),
                          description: _descCtlr.text.trim(),
                          category: _category,
                          defaultEventVisibility: 'public',
                        );

                        if (id != null) {
                          // Increment group creation count
                          await CreationLimitService().incrementGroupCount();
                          String? logoUrl;
                          String? bannerUrl;
                          if (_logoFile != null) {
                            logoUrl =
                                await FirebaseStorageHelper.uploadOrganizationImage(
                                  organizationId: id,
                                  imageFile: _logoFile!,
                                  isBanner: false,
                                );
                          }
                          if (_bannerFile != null) {
                            bannerUrl =
                                await FirebaseStorageHelper.uploadOrganizationImage(
                                  organizationId: id,
                                  imageFile: _bannerFile!,
                                  isBanner: true,
                                );
                          }
                          if (logoUrl != null || bannerUrl != null) {
                            await FirebaseFirestore.instance
                                .collection('Organizations')
                                .doc(id)
                                .update({
                                  if (logoUrl != null) 'logoUrl': logoUrl,
                                  if (bannerUrl != null) 'bannerUrl': bannerUrl,
                                });
                          }
                          if (mounted) {
                            setState(() => _submitting = false);
                            Navigator.pop(context, id);
                          }
                        } else {
                          if (mounted) {
                            setState(() => _submitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Failed to create group (name may be taken)',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create Group'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  final String label;
  final String hint;
  final File? file;
  final VoidCallback onClear;
  final VoidCallback onPick;
  final bool isBanner;

  const _ImagePickerTile({
    required this.label,
    required this.hint,
    required this.file,
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
              if (file != null)
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
              child: file == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Color(0xFF6B7280),
                        ),
                        SizedBox(height: 6),
                        Text('Tap to select image'),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        file!,
                        width: double.infinity,
                        height: isBanner ? 120 : 100,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
