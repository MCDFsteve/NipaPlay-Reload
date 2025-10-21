# 性能调优

Flutter OpenHarmony化的工程，也可以使用devtools对Dart代码进行调试，具体内容请参考 [DevTools](https://docs.flutter.cn/tools/devtools)

[性能分析定界(OpenHarmony平台)指南](./性能分析定界指南.md)

[性能分析第一步-梳理线程顺序](./性能分析第一步-梳理线程顺序.md)

[性能分析-帧渲染跟踪](./性能分析-帧渲染跟踪.md)

[性能分析-滑动响应时延](./性能分析-滑动响应时延.md)

[性能调优-图片加载](./性能调优-图片加载.md)
## 环境配置

如果环境变量中设置了代理 http_proxy 和 https_proxy，需要再设置一个环境变量 no_proxy：

```
export no_proxy=::1,127.0.0.1,localhost
```

可以通过 `flutter doctor -v` 命令检测Flutter开发环境是否配置正确。
