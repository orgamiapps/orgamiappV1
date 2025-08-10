import 'package:flutter/material.dart';
import 'package:orgami/firebase/organization_helper.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() => _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtlr = TextEditingController();
  final _descCtlr = TextEditingController();
  String _category = 'Business';
  String _defaultVisibility = 'public';
  bool _submitting = false;

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
              TextFormField(
                controller: _nameCtlr,
                decoration: const InputDecoration(labelText: 'Organization Name*'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtlr,
                decoration: const InputDecoration(labelText: 'Description'),
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
                  DropdownMenuItem(value: 'public', child: Text('Default Public')),
                  DropdownMenuItem(value: 'private', child: Text('Default Private')),
                ],
                onChanged: (v) => setState(() => _defaultVisibility = v ?? 'public'),
                decoration: const InputDecoration(labelText: 'Default Event Visibility'),
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
                        setState(() => _submitting = false);
                        if (!mounted) return;
                        if (id != null) {
                          Navigator.pop(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to create organization')),
                          );
                        }
                      },
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create'),
              )
            ],
          ),
        ),
      ),
    );
  }
}