# Environment

For details about how to set up the Flutter development environment, see https://gitcode.com/openharmony-tpc/flutter_flutter/blob/master/README.en.md

## Recommended Development Tools and Their Versions

### Flutter 3.7.12-ohos

1. python3.8 - python3.11
2. java17
3. node18
4. ohpm1.6+
5. HamonyOS SDK api11
6. Xcode14.3

## Failure in Running flutter pub get in an Offline Environment

Solution:
Add the **--offline** parameter. Complete instruction: `flutter pub get --offline`.

## Failure in Building an Application of the Release Version in the macOS Environment

Error log:
```log
ProcessPackageException: ProcessException: Found candidates, but lacked sufficient permissions to excute "/Users/xxx/ohos/src/out/ohos_release_arm64/clang_arm4/dart".
  Command: /Users/xxx/ohos/src/out/ohos_release_arm64/clang_arm4/dart
```

Solution:<br>Add the execution permission.

```sh
chmod -R +x /Users/xxx/ohos/src/out/ohos_release_arm64/*
```

In the macOS environment, you may need to manually click `dart` and `gen_snapshot` in the **src/out/ohos_release_arm64/clang_arm64** directory and allow the application to run in **Settings** > **Privacy and Security** > **Security**.

## Failure in Running a Flutter Program That Is Copied from Windows to Linux or macOS

Error log:
```log
curl: (3) Illegal characters found in URL
xxx/flutter_flutter/bin/internal/update_dart_sdk.sh: line 156: return: can only return from a function or sourced script
curl: (3) Illegal characters found in URL
```

Problem analysis:<br>The newline character on Windows is inconsistent with that on Linux or macOS.

Solution:

```sh
# Replace the newline character in the target_file from CRLF (\r\n) to LF (\n).
sed -i "s/\r//" target_file
# Replace the newline characters in bin/dart, bin/*.sh, and bin/internal/*.version with LF.
cd flutter
## Execute the following instruction in the Linux environment:
sed -i "s/\r//" bin/dart $(find bin -name "*.sh") $(find bin -name "*.version")
## Execute the following instruction in the macOS environment:
sed -i "" "s/\r//" bin/dart $(find bin -name "*.sh") $(find bin -name "*.version")
```

## Configuring ~/.npmrc

```sh
registry=https://repo.huaweicloud.com/repository/npm/
@ohos:registry=https://repo.harmonyos.com/npm/
strict-ssl=false
# Set a proxy.
# http_proxy=http://user:password@host:8080
# https_proxy=http://user:password@host:8080
```

## Configuring ~/.ohpmrc

```sh
registry=https://repo.harmonyos.com/ohpm/
strict_ssl=false
# Set a proxy.
# http_proxy=http://user:password@host:8080
# https_proxy=http://user:password@host:8080
```

## Default Counter Application Crashes When Running in the Emulator

Problem analysis:

- **FloatingActionButton** is not supported by the Emulator. You need to comment out **FloatingActionButton** in **lib/main.dart** before running the application on the Emulator.
- Reference:<br>[Differences Between the Emulator and Real Device](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-specification).

## [ios][release] GeneratedPluginRegistrant.m Module Not Found

Problem analysis:<br>A Flutter plugin is added to the **pubspec.yaml** file, but the **pod** reference related to the plugin does not exist in the **Podfile**.

Solution:<br>Run the instruction `rm ios/podfile && flutter clean && flutter run -d <ios_device>`.

Reference:<br>[GeneratedPluginRegistrant.m Module not found](https://github.com/flutter/flutter/issues/43986)

## [Windows] The flutter doctor -v Command Does Not Respond

Symptom:<br>After the environment variables are configured, the system does not respond when the **flutter doctor -v** command is executed.

Cause:<br>The proxy may not be properly configured.

Solution:
- Configure **http_proxy**, **https_proxy**, and **no_proxy** in the system environment variables.
- To configure **http_proxy** and **https_proxy**, follow the procedure of the proxy configuration in DevEco Studio.
- To configure **no_proxy**, in addition to following the procedure of the proxy configuration in DevEco Studio, you need to add the following information to the environment variables on the local host:
     - localhost
     - ::1
     - 127.0.0.1     

If the execution result contains Flutter and OpenHarmony, it indicates that the basic environment is correctly configured and both platforms are supported on Windows.
![](../media/08/error.png)