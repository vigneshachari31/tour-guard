import 'package:shared_preferences/shared_preferences.dart';

class TouristProfile {
  final String name;
  final String email;
  final String phone;
  final String bloodGroup;
  final String emergencyContact;
  final String medicalNotes;
  final String allergies;

  const TouristProfile({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.bloodGroup = '',
    this.emergencyContact = '',
    this.medicalNotes = '',
    this.allergies = '',
  });

  static const _nameKey = 'tourist_profile_name';
  static const _emailKey = 'tourist_profile_email';
  static const _phoneKey = 'tourist_profile_phone';
  static const _bloodGroupKey = 'tourist_profile_blood_group';
  static const _emergencyContactKey = 'tourist_profile_emergency_contact';
  static const _medicalNotesKey = 'tourist_profile_medical_notes';
  static const _allergiesKey = 'tourist_profile_allergies';

  static Future<TouristProfile> load() async {
    final preferences = await SharedPreferences.getInstance();
    return TouristProfile(
      name: preferences.getString(_nameKey) ?? '',
      email: preferences.getString(_emailKey) ?? '',
      phone: preferences.getString(_phoneKey) ?? '',
      bloodGroup: preferences.getString(_bloodGroupKey) ?? '',
      emergencyContact: preferences.getString(_emergencyContactKey) ?? '',
      medicalNotes: preferences.getString(_medicalNotesKey) ?? '',
      allergies: preferences.getString(_allergiesKey) ?? '',
    );
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_nameKey, name.trim()),
      preferences.setString(_emailKey, email.trim()),
      preferences.setString(_phoneKey, phone.trim()),
      preferences.setString(_bloodGroupKey, bloodGroup.trim()),
      preferences.setString(_emergencyContactKey, emergencyContact.trim()),
      preferences.setString(_medicalNotesKey, medicalNotes.trim()),
      preferences.setString(_allergiesKey, allergies.trim()),
    ]);
  }
}
