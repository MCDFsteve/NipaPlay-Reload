# FAQ

整理Flutter OpenHarmony化开发过程中的常见问题

1. [环境相关问题](./环境相关问题.md)
2. [ohos引擎产物编译相关问题](./ohos引擎产物编译相关问题.md)
3. [ohos应用编译相关问题](./ohos应用编译相关问题.md)
4. [ohos代码开发相关问题](./ohos代码开发相关问题.md)
5. [ohos运行相关问题](./ohos运行相关问题.md)
6. [功能开发相关问题](../04_development/README.md)
7. [解析flutter相关的cppcrash堆栈](./解析flutter相关的cppcrash堆栈.md)
8. [申请权限相关问题](./申请权限相关问题.md)

## Flutter OpenHarmony化应用相关问题反馈的关键信息模板

1. IDE版本号，例如：
   - DevEco-Studio 5.0.3.300
2. OpenHarmony手机或模拟器的设备名称和系统版本号，可在 "设置->关于手机" 中查看，例如：
   - HUAWEI Mate 60 Pro, 3.0.0.22(SP81xxxxxx)
   - emulator, 3.0.0.22(SP39xxxxxx)
3. flutter运行环境检测信息，例如：
   - flutter doctor -v`
4. flutter编译或运行命令，例如：
   - `flutter build hap --debug`
   - `flutter run -d $DEVICE --debug`
5. 日志文件
   - 编译或运行日志，例如：
      - `flutter build hap --debug > build.log 2>&1`
      - `flutter run -d $DEVICE --debug > run.log 2>&1`
   - hilog日志文件
      -  可通过命令导出到文件 `hdc hilog > hilog.log 2>&1`
      -  `hdc` 工具在 OpenHarmony SDK 中的 toolchains 目录下
   - 闪退日志文件
      - 可在DevEco-Studio中获取, "DevEco-Studio -> Log -> FaultLog -> 应用包名 -> cppcrash/jscrash -> 时间点 -> 鼠标右键导出日志文件"

## --local-engine 参数

flutter_flutter 在 ecd66426679c18f86a285a1ac6aa605900dcb63a (2024-06-06 20:00:49 GMT+0800) 之后的版本，`--local-engine` 成为了可选参数，可以不传。

## 提供可复现的demo

提供demo时，可以通过git删除不需要的文件，减小压缩包大小。

```sh
git init
git add -A
git commit -m "init"
git clean -dfx
```

## 物理键盘Numlock、Capslock、ScrollLock暂不支持

当前版本暂不支持。
