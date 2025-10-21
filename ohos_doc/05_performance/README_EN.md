# Performance Optimization

For a OpenHarmony Flutter project, you can use DevTools to debug the Dart code. For details, see [Flutter and Dart DevTools](https://docs.flutter.dev/tools/devtools).

[Performance Analysis and Issue Demarcation](./performance-delimitation.md)

[Performance Analysis: Sorting the Thread Sequence](./performance-threads-sequence.md)

[Performance Analysis: Frame Rendering Tracing](./performance-frame-rendering-tracking.md)

[Performance Analysis: Swipe Response Latency](./performance-sliding-response-time.md)

[Image Loading Performance Tuning](./performance-tuning-image-loading.md)

## Environment Configurations

If **http_proxy** and **https_proxy** are set in the environment variables, **no_proxy** should also be set.

```
export no_proxy=::1,127.0.0.1,localhost
```

You can execute the `flutter doctor -v` instruction to check whether the Flutter development environment is properly configured.
