import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  final ApiService? api;
  final Future<Uint8List?> Function()? pickAvatar;
  const ProfileScreen({super.key, this.api, this.pickAvatar});

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
  bool _isUploading = false;
  bool _isEditing = false;
  UserProfile? _loadedProfile;
  String? _loadError;
  Uint8List? _avatar;
  ApiService get _api => widget.api ?? ApiService.instance;

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

  void _fill(UserProfile profile) {
    _nameController.text = profile.name;
    _emailController.text = profile.email;
    _phoneController.text = profile.phone;
    _bloodGroupController.text = profile.bloodGroup;
    _emergencyContactController.text = profile.emergencyContact;
    _medicalNotesController.text = profile.medicalNotes;
    _allergiesController.text = profile.allergies;
  }

  void _handleError(Object error) {
    _showMessage(
      error is ApiException
          ? error.message
          : 'Unable to update profile. Please retry.',
      isError: true,
    );
    if (error is ApiException && error.unauthorized) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _avatar = null;
    });
    try {
      final profile = await _api.getProfile();
      if (!mounted) return;
      _loadedProfile = profile;
      _fill(profile);
      if (profile.pictureUrl != null) {
        try {
          final bytes = await _api.loadAvatar(profile.pictureUrl!);
          if (mounted) setState(() => _avatar = bytes);
        } catch (error) {
          if (mounted) _handleError(error);
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load your profile.';
      });
      _handleError(error);
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _isUploading || !_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final profile = await _api.updateProfile(
        UserProfile(
          name: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
          bloodGroup: _bloodGroupController.text,
          emergencyContact: _emergencyContactController.text,
          medicalNotes: _medicalNotesController.text,
          allergies: _allergiesController.text,
        ),
      );
      if (!mounted) return;
      setState(() {
        _loadedProfile = profile;
        _fill(profile);
        _isEditing = false;
      });
      _showMessage('Profile saved to your account.');
    } catch (error) {
      if (mounted) _handleError(error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _uploadPhoto() async {
    if (_isUploading || _isSaving) return;
    setState(() => _isUploading = true);
    try {
      Uint8List? bytes;
      if (widget.pickAvatar != null) {
        bytes = await widget.pickAvatar!();
      } else {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (image == null) return;
        if (await image.length() > 2 * 1024 * 1024) {
          throw const ApiException('Choose an image smaller than 2 MB.');
        }
        bytes = await image.readAsBytes();
      }
      if (bytes == null || !mounted) return;
      final profile = await _api.uploadAvatar(bytes);
      final saved = await _api.loadAvatar(profile.pictureUrl!);
      if (!mounted) return;
      setState(() => _avatar = saved);
      _showMessage('Profile photo saved.');
    } catch (error) {
      if (mounted) _handleError(error);
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  TextButton(
                    onPressed: _loadProfile,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width > 760
                    ? (MediaQuery.sizeOf(context).width - 700) / 2
                    : 20,
                20,
                MediaQuery.sizeOf(context).width > 760
                    ? (MediaQuery.sizeOf(context).width - 700) / 2
                    : 20,
                32,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'My profile',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: Color(0xFF1A2D4F),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isSaving || _isUploading
                              ? null
                              : () {
                                  setState(() {
                                    _isEditing = !_isEditing;
                                    if (!_isEditing && _loadedProfile != null) {
                                      _fill(_loadedProfile!);
                                    }
                                  });
                                },
                          icon: Icon(
                            _isEditing ? Icons.close : Icons.edit_outlined,
                            size: 16,
                            color: const Color(0xFF087CF0),
                          ),
                          label: Text(
                            _isEditing ? 'Cancel' : 'Edit Profile',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF087CF0),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF142C50), Color(0xFF145EA8)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24145EA8),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .4),
                                    width: 1.5,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: _isUploading || _isSaving
                                      ? null
                                      : _uploadPhoto,
                                  child: ClipOval(
                                    child: SizedBox(
                                      width: 76,
                                      height: 76,
                                      child: _isUploading
                                          ? const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            )
                                          : _avatar != null
                                          ? Image.memory(
                                              _avatar!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const Icon(
                                                    Icons.person,
                                                    size: 40,
                                                  ),
                                            )
                                          : CircleAvatar(
                                              radius: 38,
                                              backgroundColor: const Color(
                                                0xFFE8F3FF,
                                              ),
                                              child: Text(
                                                _nameController.text
                                                        .trim()
                                                        .isEmpty
                                                    ? '?'
                                                    : _nameController.text
                                                          .trim()[0]
                                                          .toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 30,
                                                  color: Color(0xFF087CF0),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: IconButton(
                                  tooltip: 'Edit profile photo',
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFF087CF0),
                                    minimumSize: const Size(32, 32),
                                    padding: const EdgeInsets.all(7),
                                    side: const BorderSide(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  onPressed: _isUploading || _isSaving
                                      ? null
                                      : _uploadPhoto,
                                  icon: const Icon(
                                    Icons.camera_alt_outlined,
                                    size: 17,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _nameController.text.trim().isEmpty
                                ? 'Add your name'
                                : _nameController.text.trim(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tourist safety profile',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFC2DCF5),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 16,
                                  color: Color(0xFF9DD9FF),
                                ),
                                SizedBox(width: 7),
                                Text(
                                  'TOUR GUARD TRAVELER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFE0F0FF),
                                  ),
                                ),
                              ],
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
                      validator: (v) => v == null || !v.contains('@')
                          ? 'Enter a valid email address'
                          : null,
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
                    if (_isEditing) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving || _isUploading
                              ? null
                              : _saveProfile,
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
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) {
    final emergency = text == 'EMERGENCY INFORMATION';
    final color = emergency ? const Color(0xFFB45345) : const Color(0xFF145EA8);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              emergency
                  ? Icons.health_and_safety_outlined
                  : Icons.badge_outlined,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emergency ? 'Emergency information' : 'Personal details',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2D4F),
                  ),
                ),
                Text(
                  emergency
                      ? 'Details that help responders assist you'
                      : 'Your details, wherever you travel',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF718198),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        readOnly: !_isEditing,
        enabled: !_isSaving && !_isUploading,
        keyboardType: keyboardType,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        validator: validator,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1A2D4F),
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 20,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: const TextStyle(color: Color(0xFF718198), fontSize: 13),
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(
            icon,
            color: _isEditing
                ? const Color(0xFF087CF0)
                : const Color(0xFF587DA5),
            size: 20,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: _isEditing
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFFE5ECF4),
            ),
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
