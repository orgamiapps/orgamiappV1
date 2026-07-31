import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class StepProfessionalInfo extends StatefulWidget {
  const StepProfessionalInfo({
    super.key,
    required this.onSkip,
    required this.onNext,
  });
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  State<StepProfessionalInfo> createState() => _StepProfessionalInfoState();
}

class _StepProfessionalInfoState extends State<StepProfessionalInfo> {
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _organizationController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  @override
  void dispose() {
    _occupationController.dispose();
    _organizationController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _textField(
            label: 'Occupation',
            controller: _occupationController,
            icon: Icons.work_outline,
            capitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(50)],
          ),
          const SizedBox(height: 16),
          _textField(
            label: 'Organization',
            controller: _organizationController,
            icon: Icons.business_outlined,
            capitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(50)],
          ),
          const SizedBox(height: 16),
          _bioField(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  child: const Text('Skip for now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AttendUsButton.primary(
                  label: 'Next',
                  onPressed: widget.onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AttendUsFormTextField(
          controller: controller,
          textCapitalization: capitalization,
          inputFormatters: inputFormatters,
          labelText: label,
          hintText: 'Enter $label (optional)',
          prefixIcon: icon,
        ),
      ],
    );
  }

  Widget _bioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AttendUsFormTextField(
          controller: _bioController,
          maxLines: 4,
          inputFormatters: [LengthLimitingTextInputFormatter(500)],
          labelText: 'Bio',
          hintText: 'Add a short bio about yourself (optional)',
          prefixIcon: Icons.edit_note_outlined,
        ),
      ],
    );
  }
}
