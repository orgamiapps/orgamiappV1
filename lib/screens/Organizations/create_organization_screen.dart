import 'package:flutter/material.dart';
import 'package:orgami/firebase/organization_helper.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/firebase/firebase_storage_helper.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() =>
      _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtlr = TextEditingController();
  final _descCtlr = TextEditingController();
  String _category = 'Business';
  String _defaultVisibility = 'public';
  bool _submitting = false;
  File? _logoFile;
  File? _bannerFile;

  final _helper = OrganizationHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Organization')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Organization Details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtlr,
                decoration: const InputDecoration(
                  labelText: 'Organization Name*',
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
                  helperText: 'What is this organization about? (optional)',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _defaultVisibility,
                items: const [
                  DropdownMenuItem(
                    value: 'public',
                    child: Text('Default Public'),
                  ),
                  DropdownMenuItem(
                    value: 'private',
                    child: Text('Default Private'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _defaultVisibility = v ?? 'public'),
                decoration: const InputDecoration(
                  labelText: 'Default Event Visibility',
                ),
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
                        setState(() => _submitting = true);
                        final id = await _helper.createOrganization(
                          name: _nameCtlr.text.trim(),
                          description: _descCtlr.text.trim(),
                          category: _category,
                          defaultEventVisibility: _defaultVisibility,
                        );

                        if (id != null) {
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
                          if (!mounted) return;
                          setState(() => _submitting = false);
                          Navigator.pop(context, id);
                        } else {
                          if (!mounted) return;
                          setState(() => _submitting = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to create organization'),
                            ),
                          );
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
                    : const Text('Create Organization'),
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
