# Developing a Plugin

This topic describes how to develop Flutter packages for the ohos platform.

## Developing a Package of the Native Plugin Type

### 1. Creating a Package

```sh
flutter create --org com.example --template=plugin --platforms=android,ios,ohos hello
```

This will create a plugin project in the **hello** directory with the following files:

`lib/hello.dart` file

Implementation of the dart plugin APIs.

`android/src/main/java/com/example/hello/HelloPlugin.kt` file

Implementation of the native plugin APIs of the Android platform (using the Kotlin programming language).

`ios/Classes/HelloPlugin.m` file

Implementation of the native plugin APIs of the iOS platform (using the Objective-C programming language).

`ohos/hello/src/main/ets/components/plugin/HelloPlugin.ets` file

Implementation of the native plugin APIs of the ohos platform (using the ArkTS programming language).

`example/` file

A Flutter application that requires a plugin and describes how to use it.

#### 1.1 Specify the supported ohos platforms.

You can specify the supported platforms by adding keys to the platforms map in **pubspec.yaml**. For example, the following is **flutter: map** of the **hello** plugin, indicating that the plugin can be used in Android, iOS, and ohos platforms:

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

### 2. Implementing a Package

#### 2.1 Define a package API.

Open the **hello** home directory and find the **lib/hello.dart** file.

#### 2.2 Compile the example.

```sh
cd hello/example
flutter pub get
flutter build hap --debug
```

#### 2.3 Add the ohos platform code (.ets).

You are advised to use DevEco Studio to compile the ohos code.

1. Start DevEco Studio and open the **hello/example/ohos** directory.
2. Configure signature information. Click **File**->**Project Structure**->**Signing Configs**->**Support HarmonyOS & Automatically generate signature**->**Sign-in**.
3. Log in with your Huawei developer account, return to DevEco Studio, and save the signature.
4. Run the project.

## Adding the Support for the ohos Platform for an Existing Plugin Project
If the existing plugin-type plugin does not support the ohos platform, you can execute the following command in the plugin root directory to add support for the ohos platform.

```sh
flutter create . --template=plugin --platforms=ohos
```

## Developing an FFI Plugin

```sh
flutter create hello --template=plugin_ffi --platforms=ohos
```

## References

1. [Developing Packages & Plugins](https://docs.flutter.dev/packages-and-plugins/developing-packages)
2. [Developing Plugin Packages](https://docs.flutter.dev/packages-and-plugins/developing-packages#plugin)
3. [OpenHarmony Documentation](https://docs.openharmony.cn/pages/v5.1/en/application-dev/application-dev-guide.md/)
4. [HarmonyOS Documentation](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/start-overview)
