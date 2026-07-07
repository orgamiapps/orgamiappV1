class CreateAccountData {
  CreateAccountData({
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.phoneNumber,
    required this.email,
    required this.dateOfBirth,
    required this.location,
  });

  final String firstName;
  final String lastName;
  final String username;
  final String? phoneNumber;
  final String? email;
  final DateTime? dateOfBirth;
  final String? location;

  String get fullName => '$firstName $lastName'.trim();

  int? get computedAge {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int age = now.year - dateOfBirth!.year;
    final hasHadBirthdayThisYear = (now.month > dateOfBirth!.month) ||
        (now.month == dateOfBirth!.month && now.day >= dateOfBirth!.day);
    if (!hasHadBirthdayThisYear) age -= 1;
    return age;
  }
}


