# Analyzing the Cpp Crash Stack Related to Flutter

This section describes how to analyze the cpp crash stack related to `libflutter.so` of OpenHarmony Flutter.

## 1. Introduction

llvm-addr2line is a tool that converts the address of a command and an executable image into a file name, a function name, and a specific line in the source code. It is generally applicable to the SO library with the **symbol** information.

## 2. Location

llvm-addr2line is stored in the **sdk** directory of DevEco Studio and Command Line Tools for OpenHarmony. The corresponding paths are as follows:

- Windows: sdk/default/openharmony/native/llvm/bin/llvm-addr2line.exe
- Linux/Mac: sdk/default/openharmony/native/llvm/bin/llvm-addr2line

You can configure the directory where llvm-addr2line is located to the environment variable **PATH**. For example:

```sh
export PATH=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin:$PATH
```

## 3. Executing Commands

```sh
llvm-addr2line -f -e so.unstripped/libflutter.so [addr1] [addr2]
```

## 4. Obtaining the libflutter.so File Containing Symbol

### 4.1 Using the Locally Built Engine Products

- Debug version
  - src/out/ohos_debug_unopt_arm64/so.unstripped/libflutter.so
- Release version
  - src/out/ohos_release_arm64/so.unstripped/libflutter.so
- Profile version
  - src/out/ohos_profile_arm64/so.unstripped/libflutter.so

### 4.2 Downloading from Cloud Products

- Find the commit ID of the `flutter_engine` version in the `flutter_flutter` version.
  - Location: `flutter_flutter/bin/internal/engine.ohos.version`
- Download the zip file of **libflutter.so** of the corresponding version based on the commit ID 8ef94277f0029e61ff6a96f630d0f10b60330cd8.
  - For debug version: https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/8ef94277f0029e61ff6a96f630d0f10b60330cd8/ohos-arm64/symbols.zip
  - For release version: https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/8ef94277f0029e61ff6a96f630d0f10b60330cd8/ohos-arm64-release/symbols.zip
  - For profile version: https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/8ef94277f0029e61ff6a96f630d0f10b60330cd8/ohos-arm64-profile/symbols.zip

## 5. Use Cases

Some crash logs related to **libflutter.so**:

```log
#00 pc 00000000001b5a34 /system/lib/ld-musl-aarch64.so.1(__timedwait_cp+188)(ef860a9c8bd64e964a4dd4ef838876e1)
#01 pc 00000000001b7a3c /system/lib/ld-musl-aarch64.so.1(__pthread_cond_timedwait+188)(ef860a9c8bd64e964a4dd4ef838876e1)
#02 pc 000000000021d450 /data/storage/el1/bundle/libs/arm64/libflutter.so(85c51e03a4f191b946582701e79e1be4a0c83959)
#03 pc 00000000001f21f4 /data/storage/el1/bundle/libs/arm64/libflutter.so(85c51e03a4f191b946582701e79e1be4a0c83959)
```

Obtain the `so.unstripped/libflutter.so` file with the symbol to convert the address in the error stack to the specific line in the error code.

Run the following command:

```sh
llvm-addr2line -f -e so.unstripped/libflutter.so 00000000001b5a34 00000000001b7a3c 000000000021d450 00000000001f21f4
```

Result:

```log
_ZNSt21_LIBCPP_ABI_NAMESPACE21__libcpp_condvar_waitB6v15004EP14pthread_cond_tP15pthread_mutex_t
/home/hazy/tools/ohos-v5.0.3.900/command-line-tools/sdk/default/openharmony/native/llvm/include/c++/v1/__threading_support:335
_ZN7flutter16PlatformViewOHOS13NotifyChangedERK7SkISize
/home/hazy/work/engine_build/engine_daily/src/out/ohos_release_arm64/../../flutter/shell/platform/ohos/platform_view_ohos.cpp:192
```

## Others

- [Analyzing Cpp Crash](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/cppcrash-guidelines-V5)
- [flutter_flutter](https://gitcode.com/openharmony-tpc/flutter_flutter)
- [flutter_engine](https://gitcode.com/openharmony-tpc/flutter_engine)
