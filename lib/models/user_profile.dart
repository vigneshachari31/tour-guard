class UserProfile {
  final String name,
      email,
      phone,
      bloodGroup,
      emergencyContact,
      medicalNotes,
      allergies;
  final String? pictureUrl;
  const UserProfile({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.bloodGroup = '',
    this.emergencyContact = '',
    this.medicalNotes = '',
    this.allergies = '',
    this.pictureUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['full_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phone: json['phone_number'] as String? ?? '',
    bloodGroup: json['blood_group'] as String? ?? '',
    emergencyContact: json['emergency_contact'] as String? ?? '',
    medicalNotes: json['medical_notes'] as String? ?? '',
    allergies: json['allergies'] as String? ?? '',
    pictureUrl: json['profile_picture_url'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'full_name': name.trim(),
    'email': email.trim(),
    'phone_number': phone.trim(),
    'blood_group': bloodGroup.trim().toUpperCase(),
    'emergency_contact': emergencyContact.trim(),
    'medical_notes': medicalNotes.trim(),
    'allergies': allergies.trim(),
  };
}
