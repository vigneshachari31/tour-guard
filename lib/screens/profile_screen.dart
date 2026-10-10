import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../services/tourist_profile_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _medicalNotesController = TextEditingController();
  final _allergiesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bloodGroupController.dispose();
    _emergencyContactController.dispose();
    _medicalNotesController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await TouristProfile.load();
      if (!mounted) return;
      _nameController.text = profile.name;
      _emailController.text = profile.email;
      _phoneController.text = profile.phone;
      _bloodGroupController.text = profile.bloodGroup;
      _emergencyContactController.text = profile.emergencyContact;
      _medicalNotesController.text = profile.medicalNotes;
      _allergiesController.text = profile.allergies;
      setState(() => _isLoading = false);
    } catch (error) {
      debugPrint('Failed to load tourist profile: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage(
        'Saved profile is unavailable. You can enter your details again.',
        isInfo: true,
      );
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await TouristProfile(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        bloodGroup: _bloodGroupController.text,
        emergencyContact: _emergencyContactController.text,
        medicalNotes: _medicalNotesController.text,
        allergies: _allergiesController.text,
      ).save();
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('Profile saved on this device.');
    } catch (error) {
      debugPrint('Failed to save tourist profile: $error');
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('Could not save profile. Please try agai.', isError: true);
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
    bool isInfo = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFDC2626)
            : isInfo
            ? const Color(0xFF334155)
            : const Color(0xFF1EAA55),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MY PROFILE',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Color(0xFF1A2D4F),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A0E4E91),
                            blurRadius: 18,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor: const Color(0xFFE8F3FF),
                            child: Text(
                              _nameController.text.trim().isEmpty
                                  ? '?'
                                  : _nameController.text
                                        .trim()[0]
                                        .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF087CF0),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _nameController.text.trim().isEmpty
                                ? 'Add your name'
                                : _nameController.text.trim(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A2D4F),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tourist safety profile',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A99AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('PERSONAL DETAILS'),
                    const SizedBox(height: 10),
                    _textField(
                      controller: _nameController,
                      label: 'Full name',
                      icon: Icons.person_outline_rounded,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter your name'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    _textField(
                      controller: _emailController,
                      label: 'Email address',
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _textField(
                      controller: _phoneController,
                      label: 'Mobile number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9+\-\s]'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _sectionTitle('EMERGENCY INFORMATION'),
                    const SizedBox(height: 10),
                    _textField(
                      controller: _bloodGroupController,
                      label: 'Blood group (optional)',
                      icon: Icons.bloodtype_outlined,
                      hintText: 'e.g. O+',
                    ),
                    _textField(
                      controller: _emergencyContactController,
                      label: 'Emergency contact',
                      icon: Icons.contact_phone_outlined,
                      keyboardType: TextInputType.phone,
                      hintText: 'Name and phone number',
                    ),
                    _textField(
                      controller: _medicalNotesController,
                      label: 'Medical notes',
                      icon: Icons.medical_information_outlined,
                      maxLines: 2,
                    ),
                    _textField(
                      controller: _allergiesController,
                      label: 'Allergies',
                      icon: Icons.warning_amber_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7E8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Color(0xFFB7791F),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Saved on this device only—not synced to an account or cloud. This prototype does not encrypt profile details.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Color(0xFF7C5A22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveProfile,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'SAVING...' : 'SAVE PROFILE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF087CF0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: Color(0xFF53647F),
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        validator: validator,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(icon, color: const Color(0xFF087CF0), size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF087CF0), width: 1.5),
          ),
        ),
      ),
    );
  }
}
