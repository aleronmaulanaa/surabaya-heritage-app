import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/place_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bookmark_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../models/review_model.dart';
import '../../services/api_service.dart';
import '../auth/login_screen.dart';

class DetailScreen extends StatefulWidget {
  final int placeId;
  const DetailScreen({super.key, required this.placeId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaceProvider>().fetchPlaceDetail(widget.placeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Consumer<PlaceProvider>(
        builder: (_, provider, __) {
          if (provider.isLoading) {
            return const Scaffold(body: LoadingWidget());
          }

          final place = provider.selectedPlace;
          if (place == null) {
            return const Scaffold(
              body: Center(child: Text('Tempat tidak ditemukan')),
            );
          }

          return CustomScrollView(
            slivers: [
              // App Bar dengan foto
              SliverAppBar(
                expandedHeight: 250,
                pinned:         true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    place.name,
                    style: const TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  background: place.photos.isNotEmpty
                      ? Image.network(
                          place.photos.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF1E3A5F),
                            child: const Icon(
                              Icons.location_city,
                              size:  80,
                              color: Colors.white54,
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF1E3A5F),
                          child: const Icon(
                            Icons.location_city,
                            size:  80,
                            color: Colors.white54,
                          ),
                        ),
                ),
                actions: [
                  // Tombol bookmark
                  Consumer2<AuthProvider, BookmarkProvider>(
                    builder: (_, auth, bookmark, __) {
                      final isBookmarked =
                          bookmark.isBookmarked(place.id);
                      return IconButton(
                        icon: Icon(
                          isBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_outline,
                          color: Colors.white,
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
                            final idx = bookmark.bookmarks
                                .indexWhere((p) => p.id == place.id);
                            if (idx != -1) {
                              await bookmark.removeBookmark(
                                bookmark.bookmarks[idx].id,
                                auth.token!,
                              );
                            }
                          } else {
                            await bookmark.addBookmark(
                              place.id,
                              auth.token!,
                            );
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
                      // Kategori & Rating
                      Row(
                        children: [
                          if (place.category != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E3A5F)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                place.category!.name,
                                style: const TextStyle(
                                  color:      Color(0xFF1E3A5F),
                                  fontWeight: FontWeight.w600,
                                  fontSize:   12,
                                ),
                              ),
                            ),
                          const Spacer(),
                          const Icon(Icons.star,
                              color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${place.avgRating.toStringAsFixed(1)} (${place.reviewCount} ulasan)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Alamat
                      _InfoRow(
                        icon:  Icons.location_on,
                        text:  place.address,
                        color: Colors.red,
                      ),
                      if (place.phone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon:  Icons.phone,
                          text:  place.phone,
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
                            icon:  Icons.language,
                            text:  place.website,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Tombol Rute
                      SizedBox(
                        width:  double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          icon:  const Icon(Icons.directions),
                          label: const Text('Buka Rute'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final url = Uri.parse(
                              'https://www.google.com/maps/dir/?api=1'
                              '&destination=${place.lat},${place.lng}'
                              '&travelmode=driving',
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Deskripsi
                      if (place.description.isNotEmpty) ...[
                        const Text(
                          'Tentang Tempat Ini',
                          style: TextStyle(
                            fontSize:   18,
                            fontWeight: FontWeight.bold,
                            color:      Color(0xFF1E3A5F),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          place.description,
                          style: const TextStyle(
                            fontSize: 14,
                            height:   1.6,
                            color:    Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Jam Buka
                      if (place.openingHours.isNotEmpty) ...[
                        const Text(
                          'Jam Buka',
                          style: TextStyle(
                            fontSize:   18,
                            fontWeight: FontWeight.bold,
                            color:      Color(0xFF1E3A5F),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding:      const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:        Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: place.openingHours
                                .map((h) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.access_time,
                                              size: 14, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(h,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Review
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Ulasan',
                            style: TextStyle(
                              fontSize:   18,
                              fontWeight: FontWeight.bold,
                              color:      Color(0xFF1E3A5F),
                            ),
                          ),
                          TextButton.icon(
                            icon:  const Icon(Icons.edit, size: 16),
                            label: const Text('Tulis Ulasan'),
                            onPressed: () =>
                                _showAddReviewDialog(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _ReviewList(reviews: place.reviews),
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

  void _showAddReviewDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    int    rating    = 5;
    final  commentCtrl = TextEditingController();

    showModalBottomSheet(
      context:     context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModalState) => Padding(
          padding: EdgeInsets.only(
            left:   24,
            right:  24,
            top:    24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tulis Ulasan',
                style: TextStyle(
                  fontSize:   18,
                  fontWeight: FontWeight.bold,
                ),
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
                    onPressed: () =>
                        setModalState(() => rating = i + 1),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Komentar
              TextField(
                controller:  commentCtrl,
                maxLines:    3,
                decoration: InputDecoration(
                  hintText: 'Tulis komentar kamu...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width:  double.infinity,
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
                    final success = await ApiService().addReview(
                      placeId: widget.placeId,
                      rating:  rating,
                      comment: commentCtrl.text.trim(),
                      token:   auth.token!,
                    );
                    if (success && context.mounted) {
                      Navigator.pop(ctx);
                      context
                          .read<PlaceProvider>()
                          .fetchPlaceDetail(widget.placeId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Ulasan berhasil ditambahkan!'),
                          backgroundColor: Colors.green,
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
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  final Color    color;

  const _InfoRow({
    required this.icon,
    required this.text,
    required this.color,
  });

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

class _ReviewList extends StatelessWidget {
  final List<ReviewModel> reviews;
  const _ReviewList({required this.reviews});

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
      children: reviews
          .map((r) => Container(
                margin:  const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_circle,
                            size: 32, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.userName ?? 'Pengguna',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Row(
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < r.rating
                                        ? Icons.star
                                        : Icons.star_outline,
                                    size:  14,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          r.createdAt.substring(0, 10),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    if (r.comment.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(r.comment,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ))
          .toList(),
    );
  }
}