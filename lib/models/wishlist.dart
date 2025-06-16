import 'package:json_annotation/json_annotation.dart';

part 'wishlist.g.dart';

@JsonSerializable()
class Wishlist {
  final String id;
  final String userId;
  final List<WishlistItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  Wishlist({
    required this.id,
    required this.userId,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Wishlist.fromJson(Map<String, dynamic> json) => _$WishlistFromJson(json);
  Map<String, dynamic> toJson() => _$WishlistToJson(this);
}

@JsonSerializable()
class WishlistItem {
  final String movieId;
  final String title;
  final String? posterPath;
  final DateTime addedAt;

  WishlistItem({
    required this.movieId,
    required this.title,
    this.posterPath,
    required this.addedAt,
  });

  factory WishlistItem.fromJson(Map<String, dynamic> json) => _$WishlistItemFromJson(json);
  Map<String, dynamic> toJson() => _$WishlistItemToJson(this);
} 