# ohos应用编译相关问题

## 配置别名，简化日常开发的编译命令

在环境变量配置文件中配置别名，简化Flutter OpenHarmony化日常使用的命令：

- windows, 使用 `Git Bash` 可以执行常见的linux命令。(使用方式：鼠标右键点击文件管理器中的空白处，左键点击 Git Bash Here)
- linux, 修改 `~/.bash_profile`。
- mac, 修改 `~/.bash_profile`, 并在 `~/.zshrc` 中加上 `source ~/.bash_profile`。

```sh
# --local-engine 参数可选，指向自行编译的engine产物，建议在 linux/mac 环境使用
export ENGINE_DIR=~/ohos/engine
export ENGINE_DEBUG=$ENGINE_DIR/src/out/ohos_debug_unopt_arm64
export ENGINE_PROFILE=$ENGINE_DIR/src/out/ohos_profile_arm64
export ENGINE_RELEASE=$ENGINE_DIR/src/out/ohos_release_arm64

alias fbuildD="flutter build hap --local-engine=$ENGINE_DEBUG --debug"
alias fbuildP="flutter build hap --local-engine=$ENGINE_PROFILE --profile"
alias fbuildR="flutter build hap --local-engine=$ENGINE_RELEASE --release"
alias frunD="flutter run -d $(hdc list targets) --local-engine=$ENGINE_DEBUG --debug"
alias frunP="flutter run -d $(hdc list targets) --local-engine=$ENGINE_PROFILE --profile"
alias frunR="flutter run -d $(hdc list targets) --local-engine=$ENGINE_RELEASE --release"
```

使用方式：

配置完成后，重新打开终端窗口，在flutter工程目录中即可使用别名编译或运行。

```sh
flutter create hello --platforms ohos
cd hello
# 编译debug版本
fbuildD
# 运行debug版本
frunD
```

## 打包release闪退、dev没问题

问题分析：

使用了debug版本的flutter.har。

解决方案：

需要应用重新打包release版本的flutter.har。

## 应用编译成功，安装后出现白屏的情况

日志信息:

```log
Reason:Signal:SIGSEGV(SEGV_MAPERR)@0x00000086e3272bf8
LastFatalMessage:Thread:547846269584[FATAL:flutter/runtime/dart_vm_initializer.cc] Error while initializing the Dart VM: Wrong full snapshot version, expected '8af474944053df1f0a3be6e6165fa7cf' found 'adb4292f3ec25074ca70abcd2d5c7251'
```

问题分析：

使用的engine产物和运行模式不一致，导致运行白屏。

解决方案：

运行或编译命令中，使用的engine产物和运行模式需要保持一致。 参考命令：

```sh
flutter run -d --debug
flutter run -d --release
flutter run -d --profile
```

## 应用编译报错，flutter插件结构重构前的版本使用了重构后的插件库

报错日志:

```log
Oops; flutter has exited unexpectedly: "type 'Null' is not a subtype of type 'List<dynamic>' in type cast".
```

解决方案:
flutter_flutter更新到master或dev的最新版本。(45bd5e627e1f1e5f4d335f205781565f576acc60, 2024-05-10)

## flutter pub get 依赖冲突报错

报错日志：

```log
Resolving dependencies...
Because flutter_cache_manager >=3.0.0-nullsafety.0 <3.3.2 depends on path_provider from hosted and flutter_cache_manager depends on path_provider from git, flutter_cache_manager >=3.0.0-nullsafety.0 <3.3.2 forbidden.
So bedause xxx depends on flutter_cache_manager 3.3.1, version solving failed.
pub get failed
...
exit code: 1
```

解决方案：

使用 `dependency_overrides` 消除依赖冲突。

```yaml
dependencies:
  flutter:
    sdk: flutter
dependency_overrides:
  path_provider:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/path_provider/path_provider
  path_provider_ohos:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/path_provider/path_provider_ohos
```

## The SDK license agreement is not accepted

日志信息:

```log
hvigor install success.
> hvigor ERROR: Cause: The SDK license agreement is not accepted.
```

问题分析：ohos工程的结构还是api11的，但是使用的sdk是api12的，这种情况下就会出现这个报错信息。

解决方案：将ohos工程结构升级为api12。  

操作步骤：
1. DevEco-Studio -> Migrate Assistant -> 5.0.0 -> Migrate
2. DevEco-Studio -> File -> Project Structure -> Compatible SDK -> 5.0.0(12)

## 通过flutter build hap -release 编译版本 会导致 app.json versionName 字段重置
背景：
查看app.json 下的versionName 字段，然后执行flutter build hap -release 编译版本进行出包。

现象：发现次字段 再次被重置1.0.0。

原因：当前规格，目前默认build会使用这个版本号。

解决：需要指定versionName和versionCode可以在build指令时加上指定版本。

参考：`flutter build hap --build-name=4.0.3 --build-number=10000`

## 应用编译报错flutter工程和依赖的插件工程不是在同一个磁盘

日志信息:

```log
ohpm ERROR: Found exception: xxx is not in the same file system as the current project, reached retry limit or non retryable error encountered.
```

问题分析：flutter工程和依赖的插件工程不是在同一个磁盘，这种情况下就会出现这个报错信息。

解决方案：Windows环境下flutter工程和依赖的插件工程需要在同一个磁盘。

## Note that you need plugins to import files that are not JavaScript

日志信息:

```log
> hvigor ERROR: Failed :entry:default@CompileArkTS...
> hvigor ERROR: Unexpected token (Note that you need plugins to import files that are not JavaScript)
```

问题分析：DevEco Studio由低版本升级到高版本，这种情况下就会出现这个报错信息。

解决方案：

修改 `hvigor-config.json5` 配置文件：

```yaml
{ 
  "modelVersion": "5.0.0",
  "dependencies": {
  },
  "properties": {
    "ohos.nativeResolver": false
  }
}
```
