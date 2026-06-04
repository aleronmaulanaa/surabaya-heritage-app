import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/place_model.dart';
import '../providers/bookmark_provider.dart';
import '../utils/constants.dart';
import '../providers/auth_provider.dart';

class PlaceCard extends StatelessWidget {
  final PlaceModel place;
  final VoidCallback onTap;

  const PlaceCard({super.key, required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final categoryColor = Color(
      AppConstants.categoryColors[place.category?.name] ?? 0xFF1E3A5F,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto + bookmark icon overlay
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  // Foto atau placeholder
                  place.photos.isNotEmpty
                      ? Image.network(
                          place.photos.first,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _buildPlaceholder(categoryColor),
                        )
                      : _buildPlaceholder(categoryColor),

                  // Bookmark icon overlay (kanan atas)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Consumer<BookmarkProvider>(
                      builder: (_, bookmark, __) {
                        final isBookmarked = bookmark.isBookmarked(place.id);
                        return AnimatedOpacity(
                          opacity: isBookmarked ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: GestureDetector(
                            onTap: isBookmarked
                                ? () async {
                                    final auth = context.read<AuthProvider>();
                                    if (auth.token == null) return;
                                    final bookmarkId = bookmark.getBookmarkId(
                                      place.id,
                                    );
                                    if (bookmarkId != null) {
                                      await bookmark.removeBookmark(
                                        bookmarkId,
                                        auth.token!,
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Bookmark dihapus'),
                                            backgroundColor: Colors.grey,
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.bookmark,
                                color: Colors.amber,
                                size: 18,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kategori badge
                  if (place.category != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: categoryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        place.category!.name,
                        style: TextStyle(
                          color: categoryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  // Nama tempat
                  Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Alamat
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place.address,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Rating dan jarak
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        place.avgRating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${place.reviewCount})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      if (place.distance != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.directions_walk,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              place.distance! < 1000
                                  ? '${place.distance!.toStringAsFixed(0)} m'
                                  : '${(place.distance! / 1000).toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(Color color) {
    return Container(
      height: 180,
      width: double.infinity,
      color: color.withOpacity(0.1),
      child: Icon(Icons.location_city, size: 60, color: color.withOpacity(0.5)),
    );
  }
}
