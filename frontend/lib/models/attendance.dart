class AttendanceRecord {
  final int     id;
  final int     employeeId;
  final String  employeeName;
  final String? profilePhotoUrl;
  final String  attendanceDate;
  final String? checkIn;
  final String? checkOut;
  final String  status;
  final double? matchScore;

  AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.profilePhotoUrl,
    required this.attendanceDate,
    this.checkIn,
    this.checkOut,
    required this.status,
    this.matchScore,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        id:              json['id'],
        employeeId:      json['employee_id'],
        employeeName:    json['employee_name'],
        profilePhotoUrl: json['profile_photo_url'],
        attendanceDate:  json['attendance_date'],
        checkIn:         json['check_in'],
        checkOut:        json['check_out'],
        status:          json['status'],
        matchScore:      json['match_score'] != null
            ? double.parse(json['match_score'].toString())
            : null,
      );
}

class TodayAttendance {
  final String               date;
  final int                  totalPresent;
  final int                  totalAbsent;
  final int                  totalLate;
  final List<AttendanceRecord> records;

  TodayAttendance({
    required this.date,
    required this.totalPresent,
    required this.totalAbsent,
    required this.totalLate,
    required this.records,
  });

  factory TodayAttendance.fromJson(Map<String, dynamic> json) => TodayAttendance(
        date:         json['date'],
        totalPresent: json['total_present'],
        totalAbsent:  json['total_absent'],
        totalLate:    json['total_late'],
        records: (json['records'] as List)
            .map((r) => AttendanceRecord.fromJson(r))
            .toList(),
      );
}
