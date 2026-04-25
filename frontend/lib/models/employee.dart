class Employee {
  final int    id;
  final int    companyId;
  final String name;
  final String? phone;
  final double monthlyScalary;
  final String joiningDate;
  final String? profilePhotoUrl;
  final String status;

  Employee({
    required this.id,
    required this.companyId,
    required this.name,
    this.phone,
    required this.monthlyScalary,
    required this.joiningDate,
    this.profilePhotoUrl,
    required this.status,
  });

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id:               json['id'],
        companyId:        json['company_id'],
        name:             json['name'],
        phone:            json['phone'],
        monthlyScalary:   double.parse(json['monthly_salary'].toString()),
        joiningDate:      json['joining_date'],
        profilePhotoUrl:  json['profile_photo_url'],
        status:           json['status'],
      );

  // Required so DropdownButton can match value against items list by identity.
  @override
  bool operator ==(Object other) => other is Employee && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
