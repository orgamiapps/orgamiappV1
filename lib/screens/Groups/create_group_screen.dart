import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase/firebase_storage_helper.dart';
import 'package:attendus/Services/creation_limit_service.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/widgets/limit_reached_dialog.dart';
import 'package:attendus/widgets/upgrade_prompt_dialog.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

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

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final subscriptionService = context.read<SubscriptionService>();
    if (!subscriptionService.canCreateGroups()) {
      await UpgradePromptDialog.showGroupsUpgrade(context);
      return;
    }

    final limitService = CreationLimitService();
    if (!limitService.canCreateGroup) {
      await LimitReachedDialog.show(
        context,
        type: 'group',
        limit: CreationLimitService.freeGroupLimit,
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
      await CreationLimitService().incrementGroupCount();
      String? logoUrl;
      String? bannerUrl;
      if (_logoFile != null) {
        logoUrl = await FirebaseStorageHelper.uploadOrganizationImage(
          organizationId: id,
          imageFile: _logoFile!,
          isBanner: false,
        );
      }
      if (_bannerFile != null) {
        bannerUrl = await FirebaseStorageHelper.uploadOrganizationImage(
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
            content: Text('Failed to create group (name may be taken)'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AttendUsTopBar(
              title: 'Create group',
              subtitle: 'Set up a community space for events and members.',
              actions: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AttendUsTokens.pageMaxWidth,
                  ),
                  child: Form(
                    key: _formKey,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        final form = Column(
                          children: [
                            _buildDetailsSection(),
                            const SizedBox(height: 16),
                            _buildBrandingSection(),
                          ],
                        );
                        return ListView(
                          padding: AttendUsTokens.pagePadding,
                          children: [
                            if (isWide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: form),
                                  const SizedBox(width: 18),
                                  SizedBox(
                                    width: 320,
                                    child: _buildReviewPanel(),
                                  ),
                                ],
                              )
                            else ...[
                              form,
                              const SizedBox(height: 16),
                              _buildReviewPanel(),
                            ],
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return AttendUsPageSection(
      title: 'Group details',
      subtitle:
          'Use a clear name and category so members understand the space.',
      icon: Icons.badge_outlined,
      framed: true,
      child: Column(
        children: [
          TextFormField(
            controller: _nameCtlr,
            decoration: const InputDecoration(
              labelText: 'Group name*',
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
            maxLines: 4,
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
        ],
      ),
    );
  }

  Widget _buildBrandingSection() {
    return AttendUsPageSection(
      title: 'Branding',
      subtitle: 'Add optional imagery for group cards and profile headers.',
      icon: Icons.photo_library_outlined,
      framed: true,
      child: Column(
        children: [
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
        ],
      ),
    );
  }

  Widget _buildReviewPanel() {
    return AttendUsPageSection(
      title: 'Review',
      subtitle: 'Groups start public for event discovery.',
      icon: Icons.fact_check_outlined,
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AttendUsListTile(
            leadingIcon: Icons.public,
            title: 'Default visibility',
            subtitle: 'Public events unless changed later',
            dense: true,
          ),
          const SizedBox(height: 10),
          AttendUsListTile(
            leadingIcon: Icons.category_outlined,
            title: 'Category',
            subtitle: _category,
            dense: true,
          ),
          const SizedBox(height: 18),
          AttendUsButton.primary(
            label: _submitting ? 'Creating...' : 'Create group',
            icon: Icons.add_business_outlined,
            onPressed: _submitting ? null : _handleSubmit,
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
    final theme = Theme.of(context);
    return AttendUsCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
              if (file != null)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(hint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: isBanner ? 120 : 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              alignment: Alignment.center,
              child: file == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.add_photo_alternate_outlined),
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
