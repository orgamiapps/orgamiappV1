import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgami/Utils/colors.dart';

class StepProfessionalInfo extends StatefulWidget {
  const StepProfessionalInfo({super.key, required this.onSkip, required this.onNext});
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
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkBlueColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: widget.onNext,
                  child: const Text(
                    'Next',
                    style: TextStyle(color: Colors.white),
                  ),
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
        Text(label,
            style: TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          textCapitalization: capitalization,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: 'Enter $label (optional)',
            filled: true,
            fillColor: Colors.grey.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: AppThemeColor.darkBlueColor, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            prefixIcon: Icon(icon, color: AppThemeColor.lightGrayColor),
          ),
        ),
      ],
    );
  }

  Widget _bioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bio',
            style: TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        TextFormField(
          controller: _bioController,
          maxLines: 4,
          inputFormatters: [LengthLimitingTextInputFormatter(500)],
          decoration: InputDecoration(
            hintText: 'Add a short bio about yourself (optional)',
            filled: true,
            fillColor: Colors.grey.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: AppThemeColor.darkBlueColor, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Icon(Icons.edit_note_outlined,
                  color: AppThemeColor.lightGrayColor),
            ),
          ),
        ),
      ],
    );
  }
}


