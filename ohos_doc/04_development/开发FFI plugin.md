# 开发FFI plugin

可参考 [开发FFI插件](https://flutter.cn/docs/packages-and-plugins/developing-packages#plugin-ffi)。

## 1. 创建 package

```sh
flutter create --template=plugin_ffi hello --platforms=android,ios,ohos
```

## 2. 构建和绑定本地原生代码

pubspec.yaml 中指定 FFI插件的平台如下：

```yaml
  plugin:
    platforms:
      android:
        ffiPlugin: true
      ohos:
        ffiPlugin: true
      ios:
        ffiPlugin: true
```

## 3. 绑定本地原生代码

为了使用本地原生代码，需要在 Dart 中进行绑定。

为了避免手工编写，它们由头文件 (src/hello.h) 中的 package:ffigen 生成。运行以下指令重新生成绑定：

```sh
dart run ffigen --config ffigen.yaml
```

## 4. 调用本地原生代码

运行时间很短的本地原生函数可以在任何 isolate 中直接调用。例如，请查看 `lib/hello.dart` 中的 sum。

运行时间较长的本地原生函数应在 [helper isolate](https://dart.cn/guides/language/concurrency#background-workers) 上调用，以避免在 Flutter 应用程序中掉帧。例如，请查看 lib/hello.dart 中的 sumAsync。
