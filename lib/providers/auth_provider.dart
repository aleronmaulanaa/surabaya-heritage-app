import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _user;
  String?    _token;
  bool       _isLoggedIn = false;
  bool       _isLoading  = false;
  String?    _errorMessage;

  UserModel? get user         => _user;
  String?    get token        => _token;
  bool       get isLoggedIn   => _isLoggedIn;
  bool       get isLoading    => _isLoading;
  String?    get errorMessage => _errorMessage;

  // Cek status login saat aplikasi dibuka
  Future<void> checkLoginStatus() async {
    _isLoggedIn = await _authService.isLoggedIn();
    if (_isLoggedIn) {
      _token = await _authService.getToken();
      _user  = await _authService.getSavedUser();
    }
    notifyListeners();
  }

  // Login
  Future<bool> login(String email, String password) async {
    _isLoading    = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.login(
      email:    email,
      password: password,
    );

    _isLoading = false;

    if (result['success']) {
      _isLoggedIn = true;
      _token      = result['token'];
      _user       = result['user'];
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message'];
      notifyListeners();
      return false;
    }
  }

  // Register
  Future<bool> register(String name, String email, String password) async {
    _isLoading    = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.register(
      name:     name,
      email:    email,
      password: password,
    );

    _isLoading = false;

    if (result['success']) {
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message'];
      notifyListeners();
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    await _authService.logout();
    _user       = null;
    _token      = null;
    _isLoggedIn = false;
    notifyListeners();
  }
}