class ReviewModel {
  final int id;
  final int placeId;
  final int userId;
  final int rating;
  final String comment;
  final String createdAt;
  final String? userName;
  final String? userAvatar;
  final String? photoUrl;
  final String? photoUrl2;
  final int editCount;

  ReviewModel({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.userName,
    this.userAvatar,
    this.photoUrl,
    this.photoUrl2,
    this.editCount = 0,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    return ReviewModel(
      id: json['id'],
      placeId: json['place_id'] ?? 0,
      userId: json['user_id'] ?? 0,
      rating: json['rating'],
      comment: json['comment'] ?? '',
      createdAt: json['created_at'] ?? '',
      userName: json['users']?['name'],
      userAvatar: json['users']?['avatar_url'],
      photoUrl: json['photo_url'],
      photoUrl2: json['photo_url_2'],
      editCount: json['edit_count'] ?? 0,
    );
  }
}
