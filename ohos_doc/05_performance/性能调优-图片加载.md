# 性能调优-图片加载

## 图片预加载

请参考：[官方图片预加载文档](https://api.flutter.dev/flutter/widgets/precacheImage.html)。

## 图片加载内存优化

参考下列的优化策略：

- 使用 `ListView.builder` 或 `GridView.builder` 可以确保只加载当前可见的图片，同时，根据业务情况可以把`ListView.builder` 或 `GridView.builder`中的`addAutomaticKeepAlives`属性值置为false，减少内存占用。
- 使用 `ResizeImage `类，`ResizeImage` 类可以在图片加载时自动调整图片尺寸，减少内存占用。
- 使用 `ImageProvider `自定义图片加载， 通过自定义 `ImageProvider`，可以完全控制图片的加载和解码过程，从而实现更高效的内存管理。也可以通过 `ResizeImage` 或自定义解码逻辑，在加载图片时调整其分辨率，从而减少内存占用。
- 使用`cached_network_image` 第三方插件，该插件提供了图片缓存和加载功能，支持占位符、错误处理和内存优化。
- 使用 `keframe`第三方插件，`keframe` 通过分帧渲染减少主线程的负担，从而提升应用的流畅性。
- 使用外接纹理方式加载图片，原生平台能很好地管理大图片或大量图片的内存，及时释放不再使用的资源，减少内存占用。
- 图片资源优化、压缩。