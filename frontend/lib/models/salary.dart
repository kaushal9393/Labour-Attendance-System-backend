class SalaryRecord {
  final int    employeeId;
  final String employeeName;
  final int    month;
  final int    year;
  final double monthlySalary;
  final int    workingDays;
  final int    presentDays;
  final int    lateDays;
  final int    absentDays;
  final double perDaySalary;
  final double deductionAmount;
  final double netPay;

  SalaryRecord({
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.year,
    required this.monthlySalary,
    required this.workingDays,
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
    required this.perDaySalary,
    required this.deductionAmount,
    required this.netPay,
  });

  factory SalaryRecord.fromJson(Map<String, dynamic> json) => SalaryRecord(
        employeeId:      json['employee_id'],
        employeeName:    json['employee_name'],
        month:           json['month'],
        year:            json['year'],
        monthlySalary:   double.parse(json['monthly_salary'].toString()),
        workingDays:     json['working_days'],
        presentDays:     json['present_days'],
        lateDays:        json['late_days'],
        absentDays:      json['absent_days'],
        perDaySalary:    double.parse(json['per_day_salary'].toString()),
        deductionAmount: double.parse(json['deduction_amount'].toString()),
        netPay:          double.parse(json['net_pay'].toString()),
      );
}
