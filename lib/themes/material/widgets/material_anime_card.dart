import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';

class MaterialAnimeCard extends StatefulWidget {
  final String name;
  final String imageUrl;
  final VoidCallback onTap;
  final bool isOnAir;
  final String? source;
  final double? rating;
  final Map<String, dynamic>? ratingDetails;
  final bool delayLoad;
  final bool useLegacyImageLoadMode;
  final bool enableBackgroundBlur;
  final bool enableShadow;
  final double backgroundBlurSigma;

  const MaterialAnimeCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.isOnAir = false,
    this.source,
    this.rating,
    this.ratingDetails,
    this.delayLoad = false,
    this.useLegacyImageLoadMode = false,
    this.enableBackgroundBlur = false,
    this.enableShadow = true,
    this.backgroundBlurSigma = 0,
  });

  String _formatTooltip() {
    final parts = <String>[];

    if (source != null && source!.trim().isNotEmpty) {
      parts.add('来源：${source!.trim()}');
    }

    final bangumi = ratingDetails?['Bangumi评分'];
    if (bangumi is num && bangumi > 0) {
      parts.add('Bangumi评分：${bangumi.toStringAsFixed(1)}');
    } else if (rating is num && (rating ?? 0) > 0) {
      parts.add('评分：${rating!.toStringAsFixed(1)}');
    }

    return parts.join('\n');
  }

  String? _primaryRatingLabel() {
    final bangumi = ratingDetails?['Bangumi评分'];
    if (bangumi is num && bangumi > 0) {
      return bangumi.toStringAsFixed(1);
    }
    if (rating != null && rating! > 0) {
      return rating!.toStringAsFixed(1);
    }
    return null;
  }

  @override
  State<MaterialAnimeCard> createState() => _MaterialAnimeCardState();
}

class _MaterialAnimeCardState extends State<MaterialAnimeCard> {
  bool _hovered = false;

  String get _displayImageUrl {
    if (kIsWeb && widget.imageUrl.startsWith('http')) {
      return '/api/image_proxy?url=${Uri.encodeComponent(widget.imageUrl)}';
    }
    return widget.imageUrl;
  }

  Widget _buildPlaceholder(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Ionicons.image_outline, size: 40),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    if (widget.imageUrl.isEmpty) {
      return _buildPlaceholder(context);
    }

    if (widget.imageUrl.startsWith('http')) {
      return CachedNetworkImageWidget(
        key: ValueKey('material_card_${widget.imageUrl}'),
        imageUrl: _displayImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        fadeDuration: Duration.zero,
        delayLoad: widget.delayLoad,
        loadMode: widget.useLegacyImageLoadMode
            ? CachedImageLoadMode.legacy
            : CachedImageLoadMode.hybrid,
        errorBuilder: (context, error) => _buildPlaceholder(context),
      );
    }

    if (kIsWeb) {
      return _buildPlaceholder(context);
    }

    return Image.file(
      File(widget.imageUrl),
      key: ValueKey('material_card_file_${widget.imageUrl}'),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: 300,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = widget._formatTooltip();
    final ratingLabel = widget._primaryRatingLabel();

    final card = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _hovered ? 1.02 : 1.0,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: widget.enableShadow ? (_hovered ? 6 : 1) : 0,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildImage(context)),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isOnAir)
                              _Badge(
                                icon: Icons.schedule_rounded,
                                label: '连载中',
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            if (ratingLabel != null) ...[
                              if (widget.isOnAir) const SizedBox(width: 6),
                              _Badge(
                                icon: Icons.star_rounded,
                                label: ratingLabel,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  height: 1.15,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.source != null && widget.source!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Text(
                      widget.source!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip.isEmpty) return card;
    return Tooltip(message: tooltip, child: card);
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
