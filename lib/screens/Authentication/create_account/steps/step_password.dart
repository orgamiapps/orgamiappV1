import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_view_model.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class StepPassword extends StatefulWidget {
  const StepPassword({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  State<StepPassword> createState() => _StepPasswordState();
}

class _StepPasswordState extends State<StepPassword> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _next() {
    if (!_formKey.currentState!.validate()) return;
    // Create account using the data collected in previous step
    final vm = context.read<CreateAccountViewModel>();
    vm.createAccount(_passwordController.text).then((ok) {
      if (ok) {
        // Proceed to profile photo step
        widget.onNext();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _passwordField(),
            const SizedBox(height: 16),
            _confirmField(),
            const SizedBox(height: 24),
            _nextButton(),
          ],
        ),
      ),
    );
  }

  Widget _passwordField() => _field(
    label: 'Password',
    controller: _passwordController,
    obscure: _obscure1,
    toggle: () => setState(() => _obscure1 = !_obscure1),
    validator: (v) {
      if (v == null || v.isEmpty) return 'Please enter a password';
      if (v.length < 6) return 'At least 6 characters';
      return null;
    },
  );

  Widget _confirmField() => _field(
    label: 'Confirm Password',
    controller: _confirmController,
    obscure: _obscure2,
    toggle: () => setState(() => _obscure2 = !_obscure2),
    validator: (v) {
      if (v == null || v.isEmpty) return 'Please confirm your password';
      if (v != _passwordController.text) return 'Passwords do not match';
      return null;
    },
  );

  Widget _field({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback toggle,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AttendUsFormTextField(
          controller: controller,
          labelText: label,
          hintText: label,
          prefixIcon: Icons.lock_outline,
          obscureText: obscure,
          suffixIcon: IconButton(
            tooltip: obscure ? 'Show password' : 'Hide password',
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: toggle,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _nextButton() {
    return Consumer<CreateAccountViewModel>(
      builder: (context, vm, child) {
        return SizedBox(
          width: double.infinity,
          child: AttendUsButton.primary(
            label: 'Create account',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: vm.isCreating ? null : _next,
            loading: vm.isCreating,
          ),
        );
      },
    );
  }
}
