# 开发plugin

本文介绍了如何开发ohos平台的 Flutter Packages。

## 开发原生插件类型的Packages

### 1. 创建Package

```sh
flutter create --org com.example --template=plugin --platforms=android,ios,ohos hello
```

这将在 hello 目录下创建一个插件项目，其中包含以下内容:

`lib/hello.dart` 文件：Dart 插件 API 实现。

`android/src/main/java/com/example/hello/HelloPlugin.kt` 文件：Android 平台原生插件 API 实现（使用 Kotlin 编程语言）。

`ios/Classes/HelloPlugin.m` 文件：iOS 平台原生插件 API 实现（使用 Objective-C 编程语言）。

`ohos/hello/src/main/ets/components/plugin/HelloPlugin.ets` 文件：Ohos 平台原生插件 API 实现 (使用 ArkTS 编程语言)。

`example/` 文件：
一个依赖于该插件并说明了如何使用它的 Flutter 应用。

#### 指定支持Ohos平台

插件可以通过向 pubspec.yaml 中的 platforms map 添加 keys 来指定其支持的平台。例如，以下是 hello 插件的 flutter: map，它支持Android、iOS和Ohos：

```yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.example.hello
        pluginClass: HelloPlugin
      ios:
        pluginClass: HelloPlugin
      ohos:
        pluginClass: HelloPlugin

environment:
  sdk: ">=2.19.6 <3.0.0"
  flutter: ">=2.5.0"
```

### 2. 实现Package

#### 2.1 定义package API

打开 hello 主目录，并找到 lib/hello.dart 文件。

#### 2.2 编译example

```sh
cd hello/example
flutter pub get
flutter build hap --debug
```

#### 2.2 添加 Ohos 平台代码 (.ets)

建议使用 DevEco-Studio 来编译 Ohos 代码。

1. 启动 DevEco-Studio，打开 hello/example/ohos 目录。
2. 配置签名信息: File->Project Structure->Signing Configs->Support HarmonyOS & Automatically generate signature->Sign in。
3. 在打开的网页中登录华为开发者账号，然后回到DevEco-Studio，保存签名信息。
4. 运行项目。

## 为现有的插件项目加入ohos平台的支持
如果现有plugin类型插件未支持ohos平台，可在插件根目录执行如下指令，用于添加对ohos平台的支持。

```sh
flutter create . --template=plugin --platforms=ohos
```

## 开发FFI插件

```sh
flutter create hello --template=plugin_ffi --platforms=ohos
```

## 参考文档

1. [Flutter Packages 的开发和提交](https://flutter.cn/docs/packages-and-plugins/developing-packages)
2. [开发原生插件](https://flutter.cn/docs/packages-and-plugins/developing-packages#plugin)
3. [OpenHarmony文档](https://docs.openharmony.cn/pages/v5.1/zh-cn/application-dev/application-dev-guide.md/)
4. [HarmonyOS文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/start-overview)
