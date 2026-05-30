class ReviewModel {
  final int id;
  final int placeId;
  final int userId;
  final int rating;
  final String comment;
  final String createdAt;
  final String? userName;
  final String? userAvatar;

  ReviewModel({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.userName,
    this.userAvatar,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    return ReviewModel(
      id:         json['id'],
      placeId:    json['place_id'],
      userId:     json['user_id'],
      rating:     json['rating'],
      comment:    json['comment'] ?? '',
      createdAt:  json['created_at'] ?? '',
      userName:   json['users']?['name'],
      userAvatar: json['users']?['avatar_url'],
    );
  }
}