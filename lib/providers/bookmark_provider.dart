import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../services/api_service.dart';

class BookmarkProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<PlaceModel> _bookmarks    = [];
  List<Map<String, dynamic>> _rawBookmarks = [];
  bool             _isLoading    = false;
  String?          _errorMessage;

  List<PlaceModel> get bookmarks    => _bookmarks;
  bool             get isLoading    => _isLoading;
  String?          get errorMessage => _errorMessage;

  // Ambil daftar bookmark
  Future<void> fetchBookmarks(String token) async {
    _isLoading    = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _rawBookmarks = await _apiService.getBookmarksRaw(token);
      _bookmarks    = _rawBookmarks
          .where((e) => e['places'] != null)
          .map((e) => PlaceModel.fromJson(e['places']))
          .toList();
    } catch (e) {
      _errorMessage = 'Gagal memuat bookmark';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Tambah bookmark
  Future<bool> addBookmark(int placeId, String token) async {
    final success = await _apiService.addBookmark(placeId, token);
    if (success) await fetchBookmarks(token);
    return success;
  }

  // Hapus bookmark
  Future<bool> removeBookmark(int bookmarkId, String token) async {
    final success = await _apiService.removeBookmark(bookmarkId, token);
    if (success) await fetchBookmarks(token);
    return success;
  }

  // Cek apakah tempat sudah dibookmark
  bool isBookmarked(int placeId) {
    return _bookmarks.any((p) => p.id == placeId);
  }

  int? getBookmarkId(int placeId) {
    final idx = _rawBookmarks
        .indexWhere((e) => e['places']?['id'] == placeId);
    return idx != -1 ? _rawBookmarks[idx]['id'] : null;
  }
}