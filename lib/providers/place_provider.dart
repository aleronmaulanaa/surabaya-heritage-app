import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../models/category_model.dart';
import '../services/api_service.dart';
import 'package:geolocator/geolocator.dart';

class PlaceProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<PlaceModel>    _places            = [];
  List<PlaceModel>    _filteredPlaces    = [];
  List<CategoryModel> _categories        = [];
  PlaceModel?         _selectedPlace;
  bool                _isLoading         = false; // untuk list
  bool                _isDetailLoading   = false; // untuk detail
  String?             _errorMessage;
  int?                _selectedCategoryId;
  String              _searchQuery    = '';
  double?             _userLat;
  double?             _userLng;

  List<PlaceModel>    get places             => _filteredPlaces;
  List<PlaceModel>    get allPlaces          => _places;
  List<CategoryModel> get categories         => _categories;
  PlaceModel?         get selectedPlace      => _selectedPlace;
  bool                get isLoading          => _isLoading;
  bool                get isDetailLoading    => _isDetailLoading;
  String?             get errorMessage       => _errorMessage;
  int?                get selectedCategoryId => _selectedCategoryId;
  String              get searchQuery        => _searchQuery;
  double?             get userLat            => _userLat;
  double?             get userLng            => _userLng;

  Future<void> fetchPlaces() async {
    _isLoading    = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _places = await _apiService.getPlaces();
      _applyFilter();
    } catch (e) {
      _errorMessage = 'Gagal memuat data tempat';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchCategories() async {
    try {
      _categories = await _apiService.getCategories();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Gagal memuat kategori';
    }
  }

  // Gunakan _isDetailLoading — tidak ganggu list di home
  Future<void> fetchPlaceDetail(int id) async {
    _isDetailLoading = true;
    notifyListeners();

    try {
      _selectedPlace = await _apiService.getPlaceDetail(id);
    } catch (e) {
      _errorMessage = 'Gagal memuat detail tempat';
    }

    _isDetailLoading = false;
    notifyListeners();
  }

  void filterByCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    _applyFilter();
    notifyListeners();
  }

  void searchPlaces(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    _filteredPlaces = _places.where((place) {
      final matchCategory = _selectedCategoryId == null ||
          place.category?.id == _selectedCategoryId;
      final matchSearch = _searchQuery.isEmpty ||
          place.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          place.address.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchCategory && matchSearch;
    }).toList();
  }

  void resetFilter() {
    _selectedCategoryId = null;
    _searchQuery        = '';
    _filteredPlaces     = _places;
    notifyListeners();
  }
  // Simpan posisi user & hitung jarak ke semua tempat
  void setUserLocation(double lat, double lng) {
    _userLat = lat;
    _userLng = lng;
    _calculateDistances();
    notifyListeners();
  }

  void _calculateDistances() {
    if (_userLat == null || _userLng == null) return;
    for (final p in _places) {
      p.distance = Geolocator.distanceBetween(
        _userLat!, _userLng!, p.lat, p.lng,
      );
    }
    _applyFilter();
  }

  // Hitung jarak ke satu tempat (untuk card & detail)
  double? distanceTo(double lat, double lng) {
    if (_userLat == null || _userLng == null) return null;
    return Geolocator.distanceBetween(_userLat!, _userLng!, lat, lng);
  }
}