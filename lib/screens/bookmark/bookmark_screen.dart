import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/place_card.dart';
import '../../widgets/loading_widget.dart';
import '../detail/detail_screen.dart';
import '../auth/login_screen.dart';

class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key});

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title:                    const Text('Tersimpan'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<AuthProvider>(
        builder: (_, auth, __) {
          // Belum login
          if (!auth.isLoggedIn) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.bookmark_outline,
                    size:  80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Masuk untuk melihat bookmark',
                    style: TextStyle(
                      fontSize: 16,
                      color:    Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A5F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('Masuk Sekarang'),
                  ),
                ],
              ),
            );
          }

          // Sudah login — tampilkan bookmark
          return Consumer<BookmarkProvider>(
            builder: (_, bookmark, __) {
              if (bookmark.isLoading) return const LoadingWidget();

              if (bookmark.errorMessage != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        bookmark.errorMessage!,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => bookmark.fetchBookmarks(
                            auth.token!),
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                );
              }

              if (bookmark.bookmarks.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bookmark_outline,
                        size:  80,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Belum ada tempat tersimpan',
                        style: TextStyle(
                          fontSize: 16,
                          color:    Colors.grey,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tekan ikon bookmark di halaman detail\nuntuk menyimpan tempat',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () =>
                    bookmark.fetchBookmarks(auth.token!),
                child: ListView.builder(
    controller: _scrollController,
    padding:     const EdgeInsets.symmetric(vertical: 8),
                  itemCount:   bookmark.bookmarks.length,
                  itemBuilder: (_, i) => PlaceCard(
                    place: bookmark.bookmarks[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(
                          placeId: bookmark.bookmarks[i].id,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}