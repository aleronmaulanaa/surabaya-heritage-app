import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../models/category_model.dart';
import '../services/api_service.dart';

class PlaceProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<PlaceModel>    _places         = [];
  List<PlaceModel>    _filteredPlaces = [];
  List<CategoryModel> _categories     = [];
  PlaceModel?         _selectedPlace;
  bool                _isLoading      = false;
  String?             _errorMessage;
  int?                _selectedCategoryId;
  String              _searchQuery    = '';

  List<PlaceModel>    get places            => _filteredPlaces;
  List<PlaceModel>    get allPlaces         => _places;
  List<CategoryModel> get categories        => _categories;
  PlaceModel?         get selectedPlace     => _selectedPlace;
  bool                get isLoading         => _isLoading;
  String?             get errorMessage      => _errorMessage;
  int?                get selectedCategoryId => _selectedCategoryId;
  String              get searchQuery       => _searchQuery;

  // Ambil semua tempat
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

  // Ambil semua kategori
  Future<void> fetchCategories() async {
    try {
      _categories = await _apiService.getCategories();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Gagal memuat kategori';
    }
  }

  // Ambil detail tempat
  Future<void> fetchPlaceDetail(int id) async {
    _isLoading = true;
    notifyListeners();

    try {
      _selectedPlace = await _apiService.getPlaceDetail(id);
    } catch (e) {
      _errorMessage = 'Gagal memuat detail tempat';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Filter berdasarkan kategori
  void filterByCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    _applyFilter();
    notifyListeners();
  }

  // Filter berdasarkan pencarian
  void searchPlaces(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  // Terapkan filter
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

  // Reset filter
  void resetFilter() {
    _selectedCategoryId = null;
    _searchQuery        = '';
    _filteredPlaces     = _places;
    notifyListeners();
  }
}