class AppConstants {
  // Base URL Backend Railway
  static const String baseUrl =
      'https://surabaya-heritage-backend-production.up.railway.app/api';

  // Nama aplikasi
  static const String appName = 'Surabaya Heritage Map';

  // Key untuk SharedPreferences
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';

  // Warna kategori
  static const Map<String, int> categoryColors = {
    'Museum': 0xFF4CAF50,
    'Monumen & Tugu': 0xFF2196F3,
    'Bangunan Kolonial': 0xFFFF9800,
    'Kawasan Bersejarah': 0xFF9C27B0,
    'Tempat Ibadah Bersejarah': 0xFFE91E63,
  };
}