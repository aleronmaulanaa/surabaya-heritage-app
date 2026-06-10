import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../providers/place_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bookmark_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../models/review_model.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../auth/login_screen.dart';

class DetailScreen extends StatefulWidget {
  final int placeId;
  const DetailScreen({super.key, required this.placeId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  bool _showAppBarTitle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaceProvider>().fetchPlaceDetail(widget.placeId);
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn && auth.token != null) {
        context.read<BookmarkProvider>().fetchBookmarks(auth.token!);
      }
    });

    _scrollController.addListener(() {
      // Judul muncul setelah scroll lebih dari tinggi foto (280px)
      final showTitle = _scrollController.offset > 230;
      if (showTitle != _showAppBarTitle) {
        setState(() => _showAppBarTitle = showTitle);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getTodayHours(List<String> hours) {
    if (hours.isEmpty) return 'Jam buka tidak tersedia';
    final days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final today = days[DateTime.now().weekday - 1];
    for (final h in hours) {
      if (h.toLowerCase().contains(today.toLowerCase())) return h;
    }
    return hours.first;
  }

  bool _isOpenNow(List<String> hours) {
    if (hours.isEmpty) return false;
    final todayHours = _getTodayHours(hours);
    final timeRegex = RegExp(r'(\d{1,2})[.:](\d{2})\s*[-–]\s*(\d{1,2})[.:](\d{2})');
    final match = timeRegex.firstMatch(todayHours);
    if (match == null) return false;
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final openMin = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    final closeMin = int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
    return nowMin >= openMin && nowMin <= closeMin;
  }

  // Foto admin di depan, foto review di belakang
  // Ganti method _getAllPhotos
  List<String> _getReviewPhotos(place) {
    final List<ReviewModel> reviews = List<ReviewModel>.from(place.reviews);
    final List<String> photos = [];
    for (final r in reviews) {
      if (r.photoUrl != null && r.photoUrl!.isNotEmpty) photos.add(r.photoUrl!);
      if (r.photoUrl2 != null && r.photoUrl2!.isNotEmpty)
        photos.add(r.photoUrl2!);
    }
    return photos;
  }

  // Total slide = admin photos + review photos
  // Jika admin kosong, slot 0 = default cover, slot 1+ = review photos
  int _totalSlides(place) {
    final adminCount = (place.photos as List).length;
    final reviewCount = _getReviewPhotos(place).length;
    if (adminCount == 0 && reviewCount == 0) return 1;
    if (adminCount == 0) return 1 + reviewCount;
    return adminCount + reviewCount;
  }

  void _openFullscreenPhoto(
    BuildContext context,
    List<String> photos,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FullscreenPhotoViewer(photos: photos, initialIndex: initialIndex),
      ),
    );
  }

  // Cek apakah user sudah pernah review tempat ini
  ReviewModel? _getUserReview(place, int userId) {
    try {
      return place.reviews.firstWhere((r) => r.userId == userId);
    } catch (_) {
      return null;
    }
  }

  IconData _getCategoryIcon(String categoryName, String placeName) {
    if (categoryName == 'Tempat Ibadah Bersejarah') {
      final lower = placeName.toLowerCase();
      if (lower.contains('masjid')) return Icons.mosque;
      if (lower.contains('gereja') || lower.contains('church'))
        return Icons.church;
      if (lower.contains('klenteng') || lower.contains('vihara'))
        return Icons.temple_hindu;
      return Icons.place;
    }
    switch (categoryName) {
      case 'Museum':
        return Icons.museum;
      case 'Monumen & Tugu':
        return Icons.account_balance;
      case 'Bangunan Kolonial':
        return Icons.domain;
      case 'Kawasan Bersejarah':
        return Icons.location_city;
      default:
        return Icons.place;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Consumer<PlaceProvider>(
        builder: (_, provider, __) {
          if (provider.isDetailLoading) {
            return const Scaffold(body: LoadingWidget());
          }

          final place = provider.selectedPlace;
          if (place == null) {
            return const Scaffold(
              body: Center(child: Text('Tempat tidak ditemukan')),
            );
          }

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                title: AnimatedOpacity(
                  opacity: _showAppBarTitle ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Builder(
                    builder: (context) {
                      final adminPhotos = place.photos as List<String>;
                      final reviewPhotos = _getReviewPhotos(place);
                      final totalSlides = _totalSlides(place);
                      final extraCount = reviewPhotos.length;

                      return Stack(
                        children: [
                          // Slideshow
                          PageView.builder(
                            controller: _pageController,
                            itemCount: totalSlides,
                            onPageChanged: (i) =>
                                setState(() => _currentPage = i),
                            itemBuilder: (_, i) {
                              final categoryName = place.category?.name ?? '';
                              final placeName = place.name.toLowerCase();
                              final categoryColor = Color(
                                AppConstants.categoryColors[place.category?.name] ?? 0xFF1E3A5F,
                              );
                              IconData coverIcon = Icons.location_city;
                              switch (categoryName) {
                                case 'Museum':             coverIcon = Icons.museum; break;
                                case 'Monumen & Tugu':     coverIcon = Icons.account_balance; break;
                                case 'Bangunan Kolonial':  coverIcon = Icons.domain; break;
                                case 'Kawasan Bersejarah': coverIcon = Icons.location_city; break;
                                case 'Tempat Ibadah Bersejarah':
                                  if (placeName.contains('masjid')) coverIcon = Icons.mosque;
                                  else if (placeName.contains('gereja') || placeName.contains('church')) coverIcon = Icons.church;
                                  else if (placeName.contains('klenteng') || placeName.contains('vihara')) coverIcon = Icons.temple_hindu;
                                  break;
                              }

                              Widget slideContent;
                              if (adminPhotos.isEmpty && i == 0) {
                                slideContent = Container(
                                  color: Color.alphaBlend(categoryColor.withOpacity(0.1), const Color(0xFF1E3A5F)),
                                  child: Icon(
                                    coverIcon,
                                    size: 80,
                                    color: categoryColor.withOpacity(0.5),
                                  ),
                                );
                              } else if (i < adminPhotos.length) {
                                slideContent = Image.network(
                                  adminPhotos[i],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Color.alphaBlend(categoryColor.withOpacity(0.1), const Color(0xFF1E3A5F)),
                                    child: Icon(
                                      coverIcon,
                                      size: 80,
                                      color: categoryColor.withOpacity(0.5),
                                    ),
                                  ),
                                );
                              } else {
                                final reviewIndex = adminPhotos.isEmpty
                                    ? i - 1
                                    : i - adminPhotos.length;
                                slideContent = Image.network(
                                  reviewPhotos[reviewIndex],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Color.alphaBlend(categoryColor.withOpacity(0.1), const Color(0xFF1E3A5F)),
                                    child: Icon(
                                      coverIcon,
                                      size: 80,
                                      color: categoryColor.withOpacity(0.5),
                                    ),
                                  ),
                                );
                              }

                              return GestureDetector(
                                onTap: () {
                                  final all = <String>[
                                    ...adminPhotos,
                                    ...reviewPhotos,
                                  ];
                                  if (all.isNotEmpty) {
                                    final idx = adminPhotos.isEmpty
                                        ? (i == 0 ? 0 : i - 1)
                                        : i;
                                    if (idx < all.length) {
                                      _openFullscreenPhoto(context, all, idx);
                                    }
                                  }
                                },
                                child: slideContent,
                              );
                            },
                          ),

                          // Dots indicator
                          if (totalSlides > 1)
                            Positioned(
                              bottom: 44,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  totalSlides,
                                  (i) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    width: _currentPage == i ? 16 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _currentPage == i
                                          ? Colors.white
                                          : Colors.white54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Hint geser + badge jumlah foto review
                          if (totalSlides > 1)
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.swipe,
                                          size: 12,
                                          color: Colors.white70,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Geser  •  ${_currentPage + 1}/$totalSlides',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (extraCount > 0) ...[
                                          const SizedBox(width: 6),
                                          const Text(
                                            '|',
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.photo_library,
                                            size: 12,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '+$extraCount dari ulasan',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                actions: [
                  Consumer2<AuthProvider, BookmarkProvider>(
                    builder: (_, auth, bookmark, __) {
                      final isBookmarked = bookmark.isBookmarked(place.id);
                      return IconButton(
                        icon: Icon(
                          isBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_outline,
                          color: isBookmarked ? Colors.amber : Colors.white,
                        ),
                        onPressed: () async {
                          if (!auth.isLoggedIn) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                            return;
                          }
                          if (isBookmarked) {
                            final bookmarkId = bookmark.getBookmarkId(place.id);
                            if (bookmarkId != null) {
                              await bookmark.removeBookmark(
                                bookmarkId,
                                auth.token!,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Bookmark dihapus'),
                                    backgroundColor: Colors.grey,
                                  ),
                                );
                              }
                            }
                          } else {
                            await bookmark.addBookmark(place.id, auth.token!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Berhasil disimpan ke bookmark!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                ],
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nama lokasi
                      Text(
                        place.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A5F),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Row kategori & rating
                      Row(
                        children: [
                          // BARU — warna sesuai kategori
                          if (place.category != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Color(
                                  AppConstants.categoryColors[place
                                          .category!
                                          .name] ??
                                      0xFF1E3A5F,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getCategoryIcon(
                                      place.category!.name,
                                      place.name,
                                    ),
                                    size: 14,
                                    color: Color(
                                      AppConstants.categoryColors[place
                                              .category!
                                              .name] ??
                                          0xFF1E3A5F,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    place.category!.name,
                                    style: TextStyle(
                                      color: Color(
                                        AppConstants.categoryColors[place
                                                .category!
                                                .name] ??
                                            0xFF1E3A5F,
                                      ),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Spacer(),
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${place.avgRating.toStringAsFixed(1)} (${place.reviewCount} ulasan)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.location_on,
                        text: place.address,
                        color: Colors.red,
                      ),
                      Consumer<PlaceProvider>(
                        builder: (_, pp, __) {
                          final dist = pp.distanceTo(place.lat, place.lng);
                          if (dist == null) return const SizedBox.shrink();
                          return Column(
                            children: [
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.directions_walk,
                                text: dist < 1000
                                    ? '${dist.toStringAsFixed(0)} m dari lokasi kamu'
                                    : '${(dist / 1000).toStringAsFixed(1)} km dari lokasi kamu',
                                color: Colors.blue,
                              ),
                            ],
                          );
                        },
                      ),
                      if (place.phone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: Icons.phone,
                          text: place.phone,
                          color: Colors.green,
                        ),
                      ],
                      if (place.website.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse(place.website);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                          child: _InfoRow(
                            icon: Icons.language,
                            text: place.website,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.directions),
                                label: const Text('Rute'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
                                  context.read<PlaceProvider>().requestRouteToPlace(place);
                                  Navigator.of(context).popUntil((route) => route.isFirst);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.map_outlined, size: 18),
                              label: const Text('Lihat di Maps', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1E3A5F),
                                side: const BorderSide(color: Color(0xFF1E3A5F)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                context.read<PlaceProvider>().requestViewPlace(place);
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (place.description.isNotEmpty) ...[
                        const Text(
                          'Tentang Tempat Ini',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A5F),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          place.description,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (place.openingHours.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              'Jam Buka',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A5F),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isOpenNow(place.openingHours)
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _isOpenNow(place.openingHours) ? 'Buka' : 'Tutup',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _isOpenNow(place.openingHours) ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: place.openingHours
                                .map(
                                  (h) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: h.toLowerCase().contains(
                                                ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu']
                                                    [DateTime.now().weekday - 1].toLowerCase(),
                                              )
                                              ? (_isOpenNow(place.openingHours) ? Colors.green : Colors.red)
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          h,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: h.toLowerCase().contains(
                                                  ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu']
                                                      [DateTime.now().weekday - 1].toLowerCase(),
                                                )
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Header ulasan + tombol tulis
                      Consumer<AuthProvider>(
                        builder: (_, auth, __) {
                          final userReview = auth.isLoggedIn
                              ? _getUserReview(place, auth.user?.id ?? 0)
                              : null;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Ulasan',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E3A5F),
                                ),
                              ),
                              if (userReview == null)
                                TextButton.icon(
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('Tulis Ulasan'),
                                  onPressed: () =>
                                      _showAddReviewDialog(context),
                                )
                              else
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                  label: const Text(
                                    'Sudah diulas',
                                    style: TextStyle(color: Colors.green),
                                  ),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Kamu sudah memberikan ulasan untuk tempat ini. Kamu bisa mengedit ulasanmu melalui detail ulasan.',
                                        ),
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Consumer<AuthProvider>(
                        builder: (_, auth, __) => _ReviewList(
                          reviews: place.reviews,
                          currentUserId: auth.user?.id,
                          onTapReview: (review) =>
                              _showReviewDetail(context, review),
                          onEditReview: (review) =>
                              _showEditReviewDialog(context, review),
                          onDeleteReview: (review) =>
                              _confirmDeleteReview(context, review),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showReviewDetail(BuildContext context, ReviewModel review) {
    final auth = context.read<AuthProvider>();
    final isOwner =
        auth.isLoggedIn && auth.user != null && auth.user!.id == review.userId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.account_circle,
                    size: 40,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review.userName ?? 'Pengguna',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < review.rating
                                  ? Icons.star
                                  : Icons.star_outline,
                              size: 16,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                        Text(
                          review.createdAt.length >= 10
                              ? review.createdAt.substring(0, 10)
                              : review.createdAt,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Menu titik tiga — hanya untuk pemilik review
                  if (isOwner)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (val) {
                        Navigator.pop(context);
                        if (val == 'edit') {
                          _showEditReviewDialog(context, review);
                        } else if (val == 'delete') {
                          _confirmDeleteReview(context, review);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          enabled: review.editCount < 2,
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit,
                                size: 16,
                                color: review.editCount < 2
                                    ? Colors.blue
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Edit Ulasan',
                                    style: TextStyle(
                                      color: review.editCount < 2
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    'Sisa edit: ${2 - review.editCount}x',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Hapus Ulasan',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (review.comment.isNotEmpty)
                Text(
                  review.comment,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              Builder(
                builder: (_) {
                  final reviewPhotos = <String>[
                    if (review.photoUrl != null && review.photoUrl!.isNotEmpty)
                      review.photoUrl!,
                    if (review.photoUrl2 != null &&
                        review.photoUrl2!.isNotEmpty)
                      review.photoUrl2!,
                  ];
                  if (reviewPhotos.isEmpty) return const SizedBox.shrink();

                  int currentPhotoPage = 0;

                  return StatefulBuilder(
                    builder: (_, setPhotoState) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          'Foto',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 1 foto — tinggi menyesuaikan aspect ratio natural
                        if (reviewPhotos.length == 1)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: GestureDetector(
                              onTap: () => _openFullscreenPhoto(
                                context,
                                reviewPhotos,
                                0,
                              ),
                              child: Image.network(
                                reviewPhotos[0],
                                fit: BoxFit.fitWidth,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          )
                        // 2 foto — slideshow dengan tinggi tetap
                        else
                          Column(
                            children: [
                              GestureDetector(
                                onTap: () => _openFullscreenPhoto(
                                  context,
                                  reviewPhotos,
                                  currentPhotoPage,
                                ),
                                onHorizontalDragEnd: (details) {
                                  if (details.primaryVelocity! < 0 &&
                                      currentPhotoPage <
                                          reviewPhotos.length - 1) {
                                    setPhotoState(() => currentPhotoPage++);
                                  } else if (details.primaryVelocity! > 0 &&
                                      currentPhotoPage > 0) {
                                    setPhotoState(() => currentPhotoPage--);
                                  }
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedSize(
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeInOut,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      transitionBuilder: (child, animation) =>
                                          FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          ),
                                      child: Image.network(
                                        reviewPhotos[currentPhotoPage],
                                        key: ValueKey(currentPhotoPage),
                                        fit: BoxFit.fitWidth,
                                        width: double.infinity,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ...List.generate(
                                    reviewPhotos.length,
                                    (i) => AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      width: currentPhotoPage == i ? 16 : 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: currentPhotoPage == i
                                            ? const Color(0xFF1E3A5F)
                                            : Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Geser',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.swipe,
                                    size: 12,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditReviewDialog(BuildContext context, ReviewModel review) {
    if (review.editCount >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Review sudah tidak bisa diedit lagi (maks 2 kali edit).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    int rating = review.rating;
    final commentCtrl = TextEditingController(text: review.comment);
    String? photoUrl = review.photoUrl;
    String? photoUrl2 = review.photoUrl2;
    bool isUploading = false;

    final originalRating = review.rating;
    final originalComment = review.comment;
    final originalPhotoUrl = review.photoUrl;
    final originalPhotoUrl2 = review.photoUrl2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        // BENAR — GestureDetector di luar Padding
        builder: (_, setModalState) => GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Ulasan',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'Sisa edit: ${2 - review.editCount}x',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Rating bintang
                  Row(
                    children: List.generate(
                      5,
                      (i) => IconButton(
                        icon: Icon(
                          i < rating ? Icons.star : Icons.star_outline,
                          color: Colors.amber,
                        ),
                        onPressed: () => setModalState(() => rating = i + 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Komentar
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    maxLength: 500,
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Tulis komentar kamu...',
                      helperText: 'Maks. 500 karakter',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (photoUrl != null && photoUrl!.isNotEmpty) ...[
                    const Text(
                      'Foto 1 saat ini:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            photoUrl!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setModalState(() => photoUrl = null),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Preview foto yang sudah ada
                  if (photoUrl2 != null && photoUrl2!.isNotEmpty) ...[
                    const Text(
                      'Foto 2 saat ini:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            photoUrl2!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setModalState(() => photoUrl2 = null),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Tombol ganti/tambah foto
                  Row(
                    children: [
                      Text(
                        photoUrl != null && photoUrl!.isNotEmpty
                            ? 'Ganti Foto:'
                            : 'Tambah Foto:',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: isUploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.photo_library, size: 16),
                        label: const Text('Galeri'),
                        onPressed: isUploading
                            ? null
                            : () async {
                                setModalState(() => isUploading = true);
                                final url = await _pickImageAndUpload(
                                  ImageSource.gallery,
                                  auth.token!,
                                );
                                setModalState(() => isUploading = false);
                                if (url != null) {
                                  // Isi photoUrl dulu, jika sudah ada isi photoUrl2
                                  if (photoUrl == null || photoUrl!.isEmpty) {
                                    setModalState(() => photoUrl = url);
                                  } else {
                                    setModalState(() => photoUrl2 = url);
                                  }
                                }
                              },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Kamera'),
                        onPressed: isUploading
                            ? null
                            : () async {
                                setModalState(() => isUploading = true);
                                final url = await _pickImageAndUpload(
                                  ImageSource.camera,
                                  auth.token!,
                                );
                                setModalState(() => isUploading = false);
                                if (url != null) {
                                  if (photoUrl == null || photoUrl!.isEmpty) {
                                    setModalState(() => photoUrl = url);
                                  } else {
                                    setModalState(() => photoUrl2 = url);
                                  }
                                }
                              },
                      ),
                    ],
                  ),
                  if (isUploading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Mengupload foto...',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (_) {
                      final hasChanged =
                          rating != originalRating ||
                          commentCtrl.text.trim() != originalComment ||
                          photoUrl != originalPhotoUrl ||
                          photoUrl2 != originalPhotoUrl2;

                      return SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasChanged
                                ? const Color(0xFF1E3A5F)
                                : Colors.grey.shade300,
                            foregroundColor: hasChanged
                                ? Colors.white
                                : Colors.grey.shade500,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: hasChanged
                              ? () async {
                                  final result = await ApiService().editReview(
                                    reviewId: review.id,
                                    rating: rating,
                                    comment: commentCtrl.text.trim(),
                                    token: auth.token!,
                                    photoUrl: photoUrl,
                                    photoUrl2: photoUrl2,
                                  );
                                  if (result['success'] == true &&
                                      context.mounted) {
                                    Navigator.pop(ctx);
                                    context
                                        .read<PlaceProvider>()
                                        .fetchPlaceDetail(widget.placeId);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Ulasan berhasil diupdate!',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } else if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result['message'] ??
                                              'Gagal mengedit ulasan',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              : null, // ← null = tombol tidak bisa ditekan
                          child: const Text('Simpan Perubahan'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteReview(BuildContext context, ReviewModel review) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Ulasan'),
        content: const Text(
          'Yakin ingin menghapus ulasan ini? Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final auth = context.read<AuthProvider>();
              final result = await ApiService().deleteReview(
                reviewId: review.id,
                token: auth.token!,
              );
              if (result['success'] == true && context.mounted) {
                context.read<PlaceProvider>().fetchPlaceDetail(widget.placeId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ulasan berhasil dihapus.'),
                    backgroundColor: Colors.grey,
                  ),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddReviewDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    int rating = 5;
    final commentCtrl = TextEditingController();
    List<String> photoUrls = [];
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        // BENAR — GestureDetector di luar Padding
        builder: (_, setModalState) => GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Tulis Ulasan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(
                      5,
                      (i) => IconButton(
                        icon: Icon(
                          i < rating ? Icons.star : Icons.star_outline,
                          color: Colors.amber,
                        ),
                        onPressed: () => setModalState(() => rating = i + 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Tulis komentar kamu...',
                      helperText: 'Maks. 500 karakter',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Tambah Foto:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: isUploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.photo_library, size: 16),
                        label: const Text('Galeri'),
                        onPressed: isUploading || photoUrls.length >= 2
                            ? null
                            : () async {
                                setModalState(() => isUploading = true);
                                final url = await _pickImageAndUpload(
                                  ImageSource.gallery,
                                  auth.token!,
                                );
                                setModalState(() => isUploading = false);
                                if (url != null) {
                                  setModalState(() => photoUrls.add(url));
                                }
                              },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Kamera'),
                        onPressed: isUploading || photoUrls.length >= 2
                            ? null
                            : () async {
                                setModalState(() => isUploading = true);
                                final url = await _pickImageAndUpload(
                                  ImageSource.camera,
                                  auth.token!,
                                );
                                setModalState(() => isUploading = false);
                                if (url != null) {
                                  setModalState(() => photoUrls.add(url));
                                }
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4), // ← TAMBAHKAN DI SINI
                  const Text(
                    'Maks. 2 foto',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if (isUploading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Mengupload foto...',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  if (photoUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: photoUrls.length,
                        itemBuilder: (_, i) => Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 80,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  photoUrls[i],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 8,
                              child: GestureDetector(
                                onTap: () =>
                                    setModalState(() => photoUrls.removeAt(i)),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final result = await ApiService().addReview(
                          placeId: widget.placeId,
                          rating: rating,
                          comment: commentCtrl.text.trim(),
                          token: auth.token!,
                          photoUrl: photoUrls.isNotEmpty ? photoUrls[0] : null,
                          photoUrl2: photoUrls.length > 1 ? photoUrls[1] : null,
                        );
                        if (result['success'] == true && context.mounted) {
                          Navigator.pop(ctx);
                          context.read<PlaceProvider>().fetchPlaceDetail(
                            widget.placeId,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ulasan berhasil ditambahkan!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result['message'] ?? 'Gagal mengirim ulasan',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: const Text('Kirim Ulasan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _pickImageAndUpload(ImageSource source, String token) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1024,
      );
      if (picked == null) return null;

      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      final base64Str = base64Encode(bytes);
      final fileName = picked.name;
      final mimeType = fileName.endsWith('.png') ? 'image/png' : 'image/jpeg';

      final response = await http
          .post(
            Uri.parse('${AppConstants.baseUrl}/upload/review-photo'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'base64': base64Str,
              'fileName': fileName,
              'mimeType': mimeType,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['photo_url'];
      }
      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal upload foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }
}

// ── Fullscreen Photo Viewer ─────────────────────────────────────
class _FullscreenPhotoViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;

  const _FullscreenPhotoViewer({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<_FullscreenPhotoViewer> {
  late PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.photos.length > 1
            ? Text('${_current + 1} / ${widget.photos.length}')
            : null,
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.network(
              widget.photos[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 80,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Info Row ────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoRow({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

// ── Review List ─────────────────────────────────────────────────
class _ReviewList extends StatelessWidget {
  final List<ReviewModel> reviews;
  final int? currentUserId;
  final void Function(ReviewModel) onTapReview;
  final void Function(ReviewModel) onEditReview;
  final void Function(ReviewModel) onDeleteReview;

  const _ReviewList({
    required this.reviews,
    required this.onTapReview,
    required this.onEditReview,
    required this.onDeleteReview,
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Belum ada ulasan. Jadilah yang pertama!',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: reviews.map((r) {
        final isOwner = currentUserId != null && r.userId == currentUserId;
        return GestureDetector(
          onTap: () => onTapReview(r),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.account_circle,
                      size: 32,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.userName ?? 'Pengguna',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < r.rating ? Icons.star : Icons.star_outline,
                                size: 14,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Tanggal + menu titik tiga (jika owner)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          r.createdAt.length >= 10
                              ? r.createdAt.substring(0, 10)
                              : r.createdAt,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        if (isOwner)
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert,
                              size: 18,
                              color: Colors.grey,
                            ),
                            onSelected: (val) {
                              if (val == 'edit') {
                                onEditReview(r);
                              } else if (val == 'delete') {
                                onDeleteReview(r);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                enabled: r.editCount < 2,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit,
                                      size: 16,
                                      color: r.editCount < 2
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: r.editCount < 2
                                                ? Colors.blue
                                                : Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          'Sisa: ${2 - r.editCount}x',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Hapus',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
                if (r.comment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    r.comment,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (r.photoUrl != null && r.photoUrl!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            r.photoUrl!,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      if (r.photoUrl2 != null && r.photoUrl2!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              r.photoUrl2!,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tap untuk detail →',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
