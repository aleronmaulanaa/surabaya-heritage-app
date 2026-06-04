class CategoryModel {
  final int id;
  final String name;
  final String icon;

  CategoryModel({
    required this.id,
    required this.name,
    required this.icon,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      icon: json['icon'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id':   id,
      'name': name,
      'icon': icon,
    };
  }
}