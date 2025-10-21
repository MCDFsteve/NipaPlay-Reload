# ohos引擎产物编译相关问题

[flutter_engine环境编译配置参考](https://gitcode.com/openharmony-tpc/flutter_engine/blob/master/README.md)

## Flutter OpenHarmony化引擎编译环境推荐配置版本

1. python 3.8-3.11, 3.12版本会出现报错
2. java 17
3. DevEco-Studio / command-line-tools , 5.0.3.300+
   - 包含了 ohpm, hvigorw, node, OpenHarmony SDK
4. Xcode14.3

## 如何生成flutter.har

1. 引擎产物编译成功后，会生成flutter.har(src/out/ohos_debug_unopt_arm64/flutter.har)
2. 复制需要的so文件（libflutter.so, profile模式需要额外复制 libvmservice_snapshot.so）到 flutter_embedding/flutter/ohos 目录后再编译，具体步骤参考 [flutter_engine文档](https://gitcode.com/openharmony-tpc/flutter_engine#embedding%E5%B1%82%E4%BB%A3%E7%A0%81%E6%9E%84%E5%BB%BA%E6%8C%87%E5%AF%BC)

## 使用 DevEco-Studio 调试 engine

参考链接：  
[Debugging-the-engine](https://github.com/flutter/engine/blob/main/docs/Debugging-the-engine.md)

