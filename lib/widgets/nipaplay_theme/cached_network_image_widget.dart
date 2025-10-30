import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'loading_placeholder.dart';
import 'package:http/http.dart' as http;

// 图片加载模式
enum CachedImageLoadMode {
  // 当前混合模式：先快速加载基础图，再通过缓存/压缩通道加载高清图
  hybrid,
  // 旧版模式（699387b 提交之前）：仅走缓存管理器的单通道加载
  legacy,
}

class CachedNetworkImageWidget extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final bool shouldRelease;
  final Duration fadeDuration;
  final bool shouldCompress;  // 新增参数，控制是否压缩图片
  final bool delayLoad;  // 新增参数，控制是否延迟加载（避免与HEAD验证竞争）
  final CachedImageLoadMode loadMode; // 新增：加载模式（hybrid/legacy）

  const CachedNetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
    this.shouldRelease = true,
    this.fadeDuration = const Duration(milliseconds: 300),
    this.shouldCompress = true,  // 默认为true，保持原有行为
    this.delayLoad = false,  // 默认false，不延迟加载
    this.loadMode = CachedImageLoadMode.hybrid, // 默认使用混合模式
  });

  @override
  State<CachedNetworkImageWidget> createState() => _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState extends State<CachedNetworkImageWidget> {
  Future<ui.Image>? _imageFuture;
  String? _currentUrl;
  bool _isImageLoaded = false;
  bool _isDisposed = false;
  ui.Image? _basicImage; // 基础图片

  Widget _buildColorPlaceholder() {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ColoredBox(color: globals.emptyBackgroundColor),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      // 不再在这里释放图片，改为由缓存管理器统一管理
      setState(() {
        _isImageLoaded = false;
      });
      _loadImage();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // 完全移除图片释放逻辑，改为依赖缓存管理器的定期清理
    super.dispose();
  }

  void _loadImage() {
    if (_currentUrl == widget.imageUrl || _isDisposed) return;
    _currentUrl = widget.imageUrl;

    if (widget.imageUrl.trim().isEmpty) {
      _imageFuture = null;
      _basicImage = null;
      return;
    }
    
    // 旧版：仅使用缓存管理器单通道加载
    if (widget.loadMode == CachedImageLoadMode.legacy) {
      _imageFuture = ImageCacheManager.instance.loadImage(widget.imageUrl);
      return;
    }

    // 混合模式：立即拉取基础图 + 异步加载高清图
    _loadBasicImage();
    
    // 异步加载高清图片
    if (widget.shouldCompress) {
      _imageFuture = ImageCacheManager.instance.loadImage(widget.imageUrl);
    } else {
      _imageFuture = _loadOriginalImage(widget.imageUrl);
    }
  }

  // 新增方法：立即加载基础图片
  void _loadBasicImage() async {
    if (widget.imageUrl.trim().isEmpty) {
      return;
    }

    // 🔥 根据delayLoad参数决定是否延迟（避免与HEAD验证竞争）
    if (widget.delayLoad) {
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    
    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      
      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(response.bodyBytes);
        final frame = await codec.getNextFrame();
        
        // 如果组件还在使用，更新基础图片
        if (mounted && !_isDisposed) {
          setState(() {
            _basicImage = frame.image;
          });
        }
      }
    } catch (e) {
      debugPrint('加载基础图片失败: $e');
    }
  }

  // 新增方法：直接加载原始图片，不进行压缩
  Future<ui.Image> _loadOriginalImage(String imageUrl) async {
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to load image');
    }
    final codec = await ui.instantiateImageCodec(response.bodyBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // 安全获取图片，添加多重保护
  ui.Image? _getSafeImage(ui.Image? image) {
    if (_isDisposed || !mounted || image == null) {
      return null;
    }
    
    try {
      // 检查图片是否仍然有效
      final width = image.width;
      final height = image.height;
      if (width <= 0 || height <= 0) {
        return null;
      }
      return image;
    } catch (e) {
      // 图片已被释放或无效
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.trim().isEmpty) {
      return _buildColorPlaceholder();
    }

    // 如果widget已被disposal，返回空容器
    if (_isDisposed) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }

    // 优先显示基础图片
    if (_basicImage != null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: SafeRawImage(
          image: _basicImage,
          fit: widget.fit,
        ),
      );
    }

    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, snapshot.error!);
          }
          return _buildColorPlaceholder();
        }

        if (snapshot.hasData) {
          // 安全获取图片
          final safeImage = _getSafeImage(snapshot.data);
          
          if (safeImage == null) {
            // 图片无效，返回占位符
            return SizedBox(
              width: widget.width,
              height: widget.height,
            );
          }

          if (!_isImageLoaded) {
            // 使用addPostFrameCallback避免在build期间调用setState
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isDisposed) {
                setState(() {
                  _isImageLoaded = true;
                });
              }
            });
          }

          // 如果禁用渐隐动画或时长为0，直接渲染，避免额外的saveLayer与图层抖动
          if (widget.fadeDuration.inMilliseconds == 0) {
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: SafeRawImage(
                image: safeImage,
                fit: widget.fit,
              ),
            );
          }

          return AnimatedOpacity(
            opacity: _isImageLoaded ? 1.0 : 0.0,
            duration: widget.fadeDuration,
            curve: Curves.easeInOut,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: SafeRawImage(
                image: safeImage,
                fit: widget.fit,
              ),
            ),
          );
        }

        return LoadingPlaceholder(
          width: widget.width ?? 160,
          height: widget.height ?? 228,
        );
      },
    );
  }
}

// 安全的RawImage包装器
class SafeRawImage extends StatelessWidget {
  final ui.Image? image;
  final BoxFit fit;

  const SafeRawImage({
    super.key,
    required this.image,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return const SizedBox.shrink();
    }

    try {
      // 再次检查图片有效性
      final _ = image!.width;
      
      return RawImage(
        image: image,
        fit: fit,
      );
    } catch (e) {
      // 图片已被释放，返回空容器
      return const SizedBox.shrink();
    }
  }
} 
