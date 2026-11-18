import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/prefs.dart';
import '../../core/theme/app_theme.dart';

/// Ported from RN `useFavorites`: favorite teams/matches persisted on device
/// (via core AppPrefs). Listen to it to rebuild on changes.
class FavoritesController extends ChangeNotifier {
  FavoritesController._();
  static final FavoritesController instance = FavoritesController._();

  Set<String> _favorites = {};
  bool loaded = false;
  Future<void>? _loading;

  Set<String> get favorites => Set.unmodifiable(_favorites);

  Future<void> load() => _loading ??= () async {
        try {
          _favorites = await AppPrefs.favorites();
        } catch (_) {}
        loaded = true;
        notifyListeners();
      }();

  bool isFavorite(String key) => _favorites.contains(key);

  Future<void> toggle(String key) async {
    if (key.isEmpty) return;
    // Optimistic update so the heart flips immediately.
    if (!_favorites.remove(key)) _favorites.add(key);
    notifyListeners();
    try {
      await AppPrefs.toggleFavorite(key);
    } catch (_) {}
  }

  @visibleForTesting
  void debugReset() {
    _favorites = {};
    loaded = false;
    _loading = null;
  }
}

/// Ported from RN `FavoriteButton`: heart toggle.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.isFavorite, required this.onToggle, this.size = 20});
  final bool isFavorite;
  final VoidCallback onToggle;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
        child: InkResponse(
          onTap: () {
            HapticFeedback.lightImpact();
            onToggle();
          },
          radius: size,
          child: Padding(
            // RN padding 4 + hitSlop 10.
            padding: const EdgeInsets.all(8),
            child: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              size: size,
              color: isFavorite ? AppColors.pitch : AppColors.textMuted,
            ),
          ),
        ),
      );
}
