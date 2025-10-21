# 解析flutter相关的cppcrash堆栈

本文介绍如何解析Flutter OpenHarmony化版本 `libflutter.so` 相关的崩溃堆栈。

## 1. 介绍

llvm-addr2line 工具是一个可以将指令的地址和可执行映像转换成文件名、函数名和源代码行数的工具。一般适用于带有 symbol 信息的so库。

## 2. 工具位置

在 **DevEco Studio** 和 **Command Line Tools for OpenHarmony** 的sdk目录下有这个工具，对应路径如下：

- Windows: sdk/default/openharmony/native/llvm/bin/llvm-addr2line.exe
- Linux/Mac: sdk/default/openharmony/native/llvm/bin/llvm-addr2line

可以将 llvm-addr2line 所在目录配置到环境变量PATH里，如

```sh
export PATH=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin:$PATH
```

## 3. 使用命令

```sh
llvm-addr2line -f -e so.unstripped/libflutter.so [addr1] [addr2]
```

## 4. 如何获取带有 symbol 的 libflutter.so 文件

#### 4.1 使用本地编译的engine产物

- debug 版本
  - src/out/ohos_debug_unopt_arm64/so.unstripped/libflutter.so
- release 版本
  - src/out/ohos_release_arm64/so.unstripped/libflutter.so
- profile 版本
  - src/out/ohos_profile_arm64/so.unstripped/libflutter.so

#### 4.2 在云端产物中下载

- 在使用的 `flutter_flutter` 版本中，找到使用的 `flutter_engine` 版本的commitid。
  - 在文件 `flutter_flutter/bin/internal/engine.ohos.version` 中。
- 根据commitid 8ef94277f0029e61ff6a96f630d0f10b60330cd8，下载对应版本 libflutter.so 的zip文件
  - debug 版本，https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/8ef94277f0029e61ff6a96f630d0f10b60330cd8/ohos-arm64/symbols.zip
  - release 版本，https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/8ef94277f0029e61ff6a96f630d0f10b60330cd8/ohos-arm64-release/symbols.zip
  - profile 版本，https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/8ef94277f0029e61ff6a96f630d0f10b60330cd8/ohos-arm64-profile/symbols.zip

## 5. 使用示例

libflutter.so 相关的部分崩溃日志：

```log
#00 pc 00000000001b5a34 /system/lib/ld-musl-aarch64.so.1(__timedwait_cp+188)(ef860a9c8bd64e964a4dd4ef838876e1)
#01 pc 00000000001b7a3c /system/lib/ld-musl-aarch64.so.1(__pthread_cond_timedwait+188)(ef860a9c8bd64e964a4dd4ef838876e1)
#02 pc 000000000021d450 /data/storage/el1/bundle/libs/arm64/libflutter.so(85c51e03a4f191b946582701e79e1be4a0c83959)
#03 pc 00000000001f21f4 /data/storage/el1/bundle/libs/arm64/libflutter.so(85c51e03a4f191b946582701e79e1be4a0c83959)
```

获取带有 symbol 的文件 `so.unstripped/libflutter.so` ，可以将错误堆栈中的地址转换为具体的报错代码行数。

执行命令：

```sh
llvm-addr2line -f -e so.unstripped/libflutter.so 00000000001b5a34 00000000001b7a3c 000000000021d450 00000000001f21f4
```

解析后的结果：

```log
_ZNSt21_LIBCPP_ABI_NAMESPACE21__libcpp_condvar_waitB6v15004EP14pthread_cond_tP15pthread_mutex_t
/home/hazy/tools/ohos-v5.0.3.900/command-line-tools/sdk/default/openharmony/native/llvm/include/c++/v1/__threading_support:335
_ZN7flutter16PlatformViewOHOS13NotifyChangedERK7SkISize
/home/hazy/work/engine_build/engine_daily/src/out/ohos_release_arm64/../../flutter/shell/platform/ohos/platform_view_ohos.cpp:192
```

## 其他

- [分析CppCrash](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/cppcrash-guidelines-V5)
- [flutter_flutter](https://gitcode.com/openharmony-tpc/flutter_flutter)
- [flutter_engine](https://gitcode.com/openharmony-tpc/flutter_engine)
