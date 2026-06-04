import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../services/api_service.dart';

class BookmarkProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<PlaceModel>             _bookmarks    = [];
  List<Map<String, dynamic>>   _rawBookmarks = [];
  bool                         _isLoading    = false;
  String?                      _errorMessage;

  List<PlaceModel> get bookmarks    => _bookmarks;
  bool             get isLoading    => _isLoading;
  String?          get errorMessage => _errorMessage;

  Future<void> fetchBookmarks(String token) async {
    // Hanya tampilkan loading jika belum ada data sama sekali
    if (_bookmarks.isEmpty) {
      _isLoading = true;
      notifyListeners();
    }
    _errorMessage = null;

    try {
      _rawBookmarks = await _apiService.getBookmarksRaw(token);

      final List<PlaceModel> parsed = [];
      for (final e in _rawBookmarks) {
        try {
          if (e['places'] != null) {
            parsed.add(PlaceModel.fromJson(e['places']));
          }
        } catch (parseErr) {
          debugPrint('[BM] PARSE ERROR: $parseErr');
        }
      }
      _bookmarks = parsed;

    } catch (e) {
      _errorMessage = 'Gagal memuat bookmark';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addBookmark(int placeId, String token) async {
    final success = await _apiService.addBookmark(placeId, token);
    if (success) await fetchBookmarks(token);
    return success;
  }

  Future<bool> removeBookmark(int bookmarkId, String token) async {
    final success = await _apiService.removeBookmark(bookmarkId, token);
    if (success) await fetchBookmarks(token);
    return success;
  }

  bool isBookmarked(int placeId) {
    return _bookmarks.any((p) => p.id == placeId);
  }

  int? getBookmarkId(int placeId) {
    final idx = _rawBookmarks
        .indexWhere((e) => e['places']?['id'] == placeId);
    return idx != -1 ? _rawBookmarks[idx]['id'] : null;
  }
}