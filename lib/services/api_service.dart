import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/place_model.dart';
import '../models/category_model.dart';
import '../models/review_model.dart';
import '../utils/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String _baseUrl = AppConstants.baseUrl;

  // ── PLACES ──────────────────────────────────────────────────

  // Ambil semua tempat (dengan filter opsional)
  Future<List<PlaceModel>> getPlaces({
    int? categoryId,
    String? search,
    String? sort,
  }) async {
    try {
      String url = '$_baseUrl/places';
      List<String> params = [];
      if (categoryId != null) params.add('category=$categoryId');
      if (search != null && search.isNotEmpty) params.add('search=$search');
      if (sort != null) params.add('sort=$sort');
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['data'];
        return list.map((e) => PlaceModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Gagal mengambil data tempat: $e');
    }
  }

  // Ambil detail satu tempat
  Future<PlaceModel?> getPlaceDetail(int id) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/places/$id'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PlaceModel.fromJson(data['data']);
      }
      return null;
    } catch (e) {
      throw Exception('Gagal mengambil detail tempat: $e');
    }
  }

  // ── CATEGORIES ───────────────────────────────────────────────

  Future<List<CategoryModel>> getCategories() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/categories'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['data'];
        return list.map((e) => CategoryModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Gagal mengambil kategori: $e');
    }
  }

  // ── REVIEWS ──────────────────────────────────────────────────

  Future<List<ReviewModel>> getReviews(int placeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/reviews?place_id=$placeId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['data'];
        return list.map((e) => ReviewModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Gagal mengambil review: $e');
    }
  }

  Future<bool> addReview({
    required int placeId,
    required int rating,
    required String comment,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/reviews'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'place_id': placeId,
          'rating':   rating,
          'comment':  comment,
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  // ── BOOKMARKS ────────────────────────────────────────────────

  Future<List<PlaceModel>> getBookmarks(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookmarks'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['data'];
        return list
            .where((e) => e['places'] != null)
            .map((e) => PlaceModel.fromJson(e['places']))
            .toList();
      }
      return [];
    } catch (e) {
      throw Exception('Gagal mengambil bookmark: $e');
    }
  }

  Future<bool> addBookmark(int placeId, String token) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookmarks'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'place_id': placeId}),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeBookmark(int bookmarkId, String token) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/bookmarks/$bookmarkId'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}