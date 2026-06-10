import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../models/category_model.dart';
import '../services/api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  bool                _sortNearest    = false;
  bool                _sortPopular    = false;
  double?             _userLat;
  double?             _userLng;
  PlaceModel?         _pendingRoutePlace;
  PlaceModel?         _pendingViewPlace;

  List<PlaceModel>    get places             => _filteredPlaces;
  List<PlaceModel>    get allPlaces          => _places;
  List<CategoryModel> get categories         => _categories;
  PlaceModel?         get selectedPlace      => _selectedPlace;
  bool                get isLoading          => _isLoading;
  bool                get isDetailLoading    => _isDetailLoading;
  String?             get errorMessage       => _errorMessage;
  int?                get selectedCategoryId => _selectedCategoryId;
  String              get searchQuery        => _searchQuery;
  bool                get sortNearest        => _sortNearest;
  bool                get sortPopular        => _sortPopular;
  double?             get userLat            => _userLat;
  double?             get userLng            => _userLng;
  PlaceModel?         get pendingRoutePlace  => _pendingRoutePlace;
  PlaceModel?         get pendingViewPlace   => _pendingViewPlace;

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

  void toggleSortNearest() {
    _sortNearest = !_sortNearest;
    _applyFilter();
    notifyListeners();
  }

  void toggleSortPopular() {
    _sortPopular = !_sortPopular;
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

    if (_sortNearest && _sortPopular) {
      _filteredPlaces.sort((a, b) {
        final da = a.distance ?? double.infinity;
        final db = b.distance ?? double.infinity;
        final distCmp = da.compareTo(db);
        if (distCmp != 0) return distCmp;
        return b.avgRating.compareTo(a.avgRating);
      });
    } else if (_sortNearest) {
      _filteredPlaces.sort((a, b) {
        final da = a.distance ?? double.infinity;
        final db = b.distance ?? double.infinity;
        return da.compareTo(db);
      });
    } else if (_sortPopular) {
      _filteredPlaces.sort((a, b) => b.avgRating.compareTo(a.avgRating));
    }
  }

  void resetFilter() {
    _selectedCategoryId = null;
    _searchQuery        = '';
    _sortNearest        = false;
    _sortPopular        = false;
    _filteredPlaces     = _places;
    notifyListeners();
  }
  void requestRouteToPlace(PlaceModel place) {
    _pendingRoutePlace = place;
    notifyListeners();
  }

  PlaceModel? consumePendingRoute() {
    final place = _pendingRoutePlace;
    _pendingRoutePlace = null;
    return place;
  }

  void requestViewPlace(PlaceModel place) {
    _pendingViewPlace = place;
    notifyListeners();
  }

  PlaceModel? consumePendingView() {
    final place = _pendingViewPlace;
    _pendingViewPlace = null;
    return place;
  }

  // Simpan posisi user & hitung jarak ke semua tempat
  void setUserLocation(double lat, double lng) {
    _userLat = lat;
    _userLng = lng;
    _calculateDistances();
    notifyListeners();
    // Hitung jarak jalan setelah GPS didapat
    _fetchRoadDistances();
  }

  Future<void> _fetchRoadDistances() async {
    if (_userLat == null || _userLng == null || _places.isEmpty) return;
    debugPrint('[ROAD] Mulai hitung jarak jalan untuk ${_places.length} tempat');

    final futures = _places.map((place) async {
      try {
        final url =
            'http://router.project-osrm.org/route/v1/driving/'
            '$_userLng,$_userLat;'
            '${place.lng},${place.lat}'
            '?overview=false';

        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
            final roadDist = (data['routes'][0]['distance'] as num).toDouble();
            debugPrint('[ROAD] ${place.name}: $roadDist m');
            place.distance = roadDist;
          }
        } else {
          debugPrint('[ROAD] GAGAL ${place.name}: status ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('[ROAD] ERROR ${place.name}: $e');
      }
    });

    await Future.wait(futures);
    debugPrint('[ROAD] Selesai, notify listeners');
    _applyFilter();
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
    // Cek apakah jarak jalan sudah tersedia di _places
    try {
      final place = _places.firstWhere(
        (p) => p.lat == lat && p.lng == lng,
      );
      if (place.distance != null) return place.distance;
    } catch (_) {}
    // Fallback: garis lurus
    return Geolocator.distanceBetween(_userLat!, _userLng!, lat, lng);
  }
}