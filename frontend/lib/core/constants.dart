class AppConstants {
  static const String baseUrl = 'https://labour-attendance-system-backend-production.up.railway.app/api';
  static const String companyCode = 'GARAGE2024';

  // Shared preference keys
  static const String keyToken     = 'jwt_token';
  static const String keyMode      = 'app_mode';   // 'kiosk' | 'admin'
  static const String keyCompanyId = 'company_id';
  static const String keyAdminName = 'admin_name';

  // App modes
  static const String modeKiosk = 'kiosk';
  static const String modeAdmin = 'admin';

  // Kiosk admin PIN (change before distributing)
  static const String kioskAdminPin = '1234';

  // Face recognition
  static const int    photoCount        = 25;
  static const double matchThreshold    = 0.80;
  static const int    successAutoReturn = 3; // seconds
  static const int    failedAutoReturn  = 4; // seconds
}
