# FAQs

You can refer to FAQs related to the following aspects during OpenHarmony Flutter development.

1. [Environment](./environment.md)
2. [ohos Engine Product Compilation](./ohos-engine-product-compilation.md)
3. [ohos Application Compilation](./ohos-application-compilation.md)
4. [ohos Code Development](./ohos-code.md)
5. [ohos Running](./ohos-run.md)
6. [Feature Development](../04_development/README_EN.md)
7. [Analyzing the Cpp Crash Stack Related to Flutter](./flutter-cppcrash-guideline.md)
8. [Permission Application Related Issues](./permission-application.md)

## Key Information Template for Feedback on Questions Related to OpenHarmony Flutter Application

1. IDE version number. Example:
   1. DevEco Studio 5.0.3.300
2. Device name and system version number of the OpenHarmony device or the Emulator. You can check them in **Settings** > **About phone**. Example:
   1. HUAWEI Mate 60 Pro, 3.0.0.22(SP81xxxxxx)
   2. Emulator, 3.0.0.22(SP39xxxxxx)
3. Information about the Flutter runtime environment. Example:
   1. `flutter doctor -v`
4. Flutter building or running instructions. Example:
   1. `flutter build hap --debug`
   2. `flutter run -d $DEVICE --debug`
5. Log files.
   1. Building or running logs. Example:
      1. `flutter build hap --debug > build.log 2>&1`
      2. `flutter run -d $DEVICE --debug > run.log 2>&1`
   2. **hilog** file
      1. Export the `hdc hilog > hilog.log 2>&1` file by using instructions.
      2. The `hdc` tool is stored in the **toolchains** directory of the HarmonyOS SDK.
   3. Log files recording crashes.
      1. You can obtain the log file from DevEco Studio. Steps: **DevEco Studio** > **Log** > **FaultLog** > **app bundle name** > **cppcrash/jscrash** > **Time** > **Right-click to export the log files**.

## --local-engine Parameters

In **flutter_flutter** of a version later than ecd66426679c18f86a285a1ac6aa605900dcb63a (20:00:49, June 6, 2024, UTC+8), the `--local-engine` parameter is optional and may not be passed.

## Providing a Demo That Can Be Reproduced

When providing a demo, you can execute **git** to delete unnecessary files to reduce the size of the application package.

```sh
git init
git add -A
git commit -m "init"
git clean -dfx
```

## Physical keyboard NumLock, CapsLock, and ScrollLock are not supported

Not supported in the current version.
