# Image Loading Performance Tuning

## Image Preloading

Please refer to：[Official Image Preloading Documentation](https://api.flutter.dev/flutter/widgets/precacheImage.html)。

## Image Loading Memory Optimization

Please refer to the optimization strategies below：

- Use 'ListView.builder' or 'GridView.builder' to ensure that only the currently visible images are loaded, and at the same time, you can set the 'addAutomaticKeepAlives' property value in 'ListView.builder' or 'GridView.builder' to false depending on your business situation to reduce memory usage.
- Use the ResizeImage class, which automatically resizes the image when it loads, reducing the memory footprint.
- Customize image loading with 'ImageProvider', by customizing 'ImageProvider', you can have full control over the image loading and decoding process, resulting in more efficient memory management. It is also possible to reduce the memory footprint by adjusting the resolution of the image when it is loaded via 'ResizeImage' or custom decoding logic.
- Use the 'cached_network_image' third-party plugin, which provides image caching and loading capabilities, support for placeholders, error handling, and memory optimization.
- Using the 'keframe' third-party plugin, 'keframe' reduces the burden on the main thread by rendering in a split frame, thus improving the smoothness of the application.
- The native platform can manage the memory of large images or a large number of images by using external textures, release resources that are no longer used in a timely manner, and reduce memory usage.
- Image resource optimization and compression.