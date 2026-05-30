import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../utils/constants.dart';

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
        margin:      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset:     const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto atau placeholder
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: place.photos.isNotEmpty
                  ? Image.network(
                      place.photos.first,
                      height:     180,
                      width:      double.infinity,
                      fit:        BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(categoryColor),
                    )
                  : _buildPlaceholder(categoryColor),
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
                        horizontal: 8, vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:        categoryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        place.category!.name,
                        style: TextStyle(
                          color:      categoryColor,
                          fontSize:   11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  // Nama tempat
                  Text(
                    place.name,
                    style: const TextStyle(
                      fontSize:   16,
                      fontWeight: FontWeight.bold,
                      color:      Color(0xFF1E3A5F),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Alamat
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place.address,
                          style: const TextStyle(
                            fontSize: 12,
                            color:    Colors.grey,
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
                          fontSize:   12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${place.reviewCount})',
                        style: const TextStyle(
                          fontSize: 12,
                          color:    Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      if (place.distance != null)
                        Row(
                          children: [
                            const Icon(Icons.directions_walk,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              place.distance! < 1000
                                  ? '${place.distance!.toStringAsFixed(0)} m'
                                  : '${(place.distance! / 1000).toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 12,
                                color:    Colors.grey,
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
      width:  double.infinity,
      color:  color.withOpacity(0.1),
      child:  Icon(Icons.location_city, size: 60, color: color.withOpacity(0.5)),
    );
  }
}