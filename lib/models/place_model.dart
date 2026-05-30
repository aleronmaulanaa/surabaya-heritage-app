import 'category_model.dart';
import 'review_model.dart';

class PlaceModel {
  final int id;
  final String name;
  final String slug;
  final String address;
  final double lat;
  final double lng;
  final String description;
  final List<String> openingHours;
  final String phone;
  final String website;
  final double avgRating;
  final int reviewCount;
  final CategoryModel? category;
  final List<String> photos;
  final List<ReviewModel> reviews;
  double? distance;

  PlaceModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.address,
    required this.lat,
    required this.lng,
    required this.description,
    required this.openingHours,
    required this.phone,
    required this.website,
    required this.avgRating,
    required this.reviewCount,
    this.category,
    required this.photos,
    required this.reviews,
    this.distance,
  });

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    // Parse opening hours
    List<String> hours = [];
    if (json['opening_hours'] != null) {
      hours = List<String>.from(json['opening_hours']);
    }

    // Parse photos
    List<String> photoList = [];
    if (json['place_photos'] != null) {
      for (var p in json['place_photos']) {
        if (p['photo_url'] != null) {
          photoList.add(p['photo_url']);
        }
      }
    }

    // Parse reviews
    List<ReviewModel> reviewList = [];
    if (json['reviews'] != null) {
      for (var r in json['reviews']) {
        reviewList.add(ReviewModel.fromJson(r));
      }
    }

    return PlaceModel(
      id:           json['id'],
      name:         json['name'] ?? '',
      slug:         json['slug'] ?? '',
      address:      json['address'] ?? '',
      lat:          (json['lat'] ?? 0).toDouble(),
      lng:          (json['lng'] ?? 0).toDouble(),
      description:  json['description'] ?? '',
      openingHours: hours,
      phone:        json['phone'] ?? '',
      website:      json['website'] ?? '',
      avgRating:    (json['avg_rating'] ?? 0).toDouble(),
      reviewCount:  json['review_count'] ?? 0,
      category:     json['categories'] != null
                      ? CategoryModel.fromJson(json['categories'])
                      : null,
      photos:       photoList,
      reviews:      reviewList,
    );
  }
}