import 'package:flutter/material.dart';

import '../controllers/favorites_controller.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_icon_button.dart';
import '../widgets/lyrics_box.dart';
import '../widgets/song_artwork.dart';
import '../widgets/song_meta_row.dart';

class FavoritesScreen extends StatefulWidget {
  final FavoritesController controller;

  const FavoritesScreen({super.key, required this.controller});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int? expandedIndex; // Track which song's details are expanded (small screen)
  int? selectedIndex; // Track which song is selected (wide screen fragment)

  // Threshold width for showing master-detail layout
  static const double wideScreenBreakpoint = 600;

  List<Song> get _favorites => widget.controller.favorites;

  Future<bool> _showRemoveConfirmation(Song song) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove from Favorites?'),
            titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            content: Text(
              'Remove "${song.title}" from your favorites?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.favorite,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _handleLongPress(int index) async {
    final favorites = _favorites;
    if (index < 0 || index >= favorites.length) return;
    final song = favorites[index];
    final confirmed = await _showRemoveConfirmation(song);
    if (confirmed && mounted) {
      setState(() {
        // Clear expanded/selected if removing that item
        if (expandedIndex == index) expandedIndex = null;
        if (selectedIndex == index) selectedIndex = null;
        // Adjust indices if removing item before them
        if (expandedIndex != null && expandedIndex! > index) {
          expandedIndex = expandedIndex! - 1;
        }
        if (selectedIndex != null && selectedIndex! > index) {
          selectedIndex = selectedIndex! - 1;
        }
      });
      // The controller is a ChangeNotifier; removing notifies our AnimatedBuilder
      // so the list rebuilds from the live source of truth.
      await widget.controller.removeFavorite(song);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final favorites = _favorites;
              return Column(
                children: [
                  _buildHeader(favorites.length),
                  Expanded(
                    child: favorites.isEmpty
                        ? _buildEmptyState()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final isWideScreen =
                                  constraints.maxWidth >= wideScreenBreakpoint;
                              if (isWideScreen) {
                                return _buildWideScreenLayout(favorites);
                              } else {
                                return _buildNarrowScreenList(favorites);
                              }
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int count) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            GlassIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Favorites',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    count == 1 ? '1 song' : '$count songs',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(
              Icons.favorite_border_rounded,
              size: 44,
              color: AppTheme.favorite.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No favorites yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the heart on a song to save it here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Wide Screen: List on left, Detail fragment on right ───────────────────
  Widget _buildWideScreenLayout(List<Song> favorites) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 24),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final song = favorites[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FavoriteCard(
                  song: song,
                  selected: selectedIndex == index,
                  onTap: () => setState(() {
                    selectedIndex = selectedIndex == index ? null : index;
                  }),
                  onLongPress: () => _handleLongPress(index),
                ),
              );
            },
          ),
        ),
        Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
        Expanded(
          flex: 3,
          child: selectedIndex != null && selectedIndex! < favorites.length
              ? _buildDetailFragment(favorites[selectedIndex!])
              : _buildSelectPrompt(),
        ),
      ],
    );
  }

  Widget _buildSelectPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 56,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a song to see details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Long press to remove from favorites',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailFragment(Song song) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: _SongThumbnail(
              song: song,
              size: 200,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            song.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SongMetaRow(
            icon: Icons.person_rounded,
            value: song.artist,
            textStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
            ),
            iconSize: 18,
            spacing: 8,
          ),
          const SizedBox(height: 6),
          SongMetaRow(
            icon: Icons.album_rounded,
            value: song.album,
            textStyle: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 14,
            ),
            iconSize: 18,
            spacing: 8,
          ),
          const SizedBox(height: 24),
          _buildLyricsHeader(),
          const SizedBox(height: 12),
          LyricsBox(
            lyrics: song.lyrics,
            textStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsHeader() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Lyrics',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ─── Narrow Screen: Expandable list with inline details ────────────────────
  Widget _buildNarrowScreenList(List<Song> favorites) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final song = favorites[index];
        final isExpanded = index == expandedIndex;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _FavoriteCard(
            song: song,
            expanded: isExpanded,
            showChevron: true,
            onTap: () => setState(() {
              expandedIndex = isExpanded ? null : index;
            }),
            onLongPress: () => _handleLongPress(index),
            details: _buildInlineDetails(song),
          ),
        );
      },
    );
  }

  Widget _buildInlineDetails(Song song) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SongMetaRow(
          icon: Icons.person_rounded,
          value: song.artist,
          textStyle: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        SongMetaRow(
          icon: Icons.album_rounded,
          value: song.album,
          textStyle: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Lyrics',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        LyricsBox(
          lyrics: song.lyrics,
          padding: const EdgeInsets.all(12),
          backgroundOpacity: 0.05,
          borderRadius: BorderRadius.circular(12),
          textStyle: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

/// A single favorite row rendered as a soft card. Optionally reveals inline
/// [details] with a smooth cross-fade (used on narrow screens).
class _FavoriteCard extends StatelessWidget {
  final Song song;
  final bool selected;
  final bool expanded;
  final bool showChevron;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget? details;

  const _FavoriteCard({
    required this.song,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.expanded = false,
    this.showChevron = false,
    this.details,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = selected || expanded;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: highlighted
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    _SongThumbnail(
                      song: song,
                      size: 56,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (showChevron)
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.favorite_rounded,
                      color: AppTheme.favorite,
                      size: 22,
                    ),
                  ],
                ),
                if (details != null)
                  AnimatedCrossFade(
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: details!,
                    ),
                    crossFadeState: expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 220),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a song's cover: real embedded album art when available, otherwise
/// the bundled placeholder asset.
class _SongThumbnail extends StatelessWidget {
  final Song song;
  final double size;
  final BorderRadius borderRadius;

  const _SongThumbnail({
    required this.song,
    required this.size,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    return SongArtwork(
      uri: song.assetPath,
      placeholderAsset: song.imageAsset,
      size: size,
      borderRadius: borderRadius,
      artworkBytes: song.artwork,
    );
  }
}
