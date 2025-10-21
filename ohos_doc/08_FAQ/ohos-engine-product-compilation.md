# ohos Engine Product Compilation

For details about how to set up the Flutter engine environment, see https://gitcode.com/openharmony-tpc/flutter_engine/blob/master/README.en.md.

## Recommended Environment Configuration Version of the OpenHarmony Flutter Engine

1. Python 3.8-3.11 (Error is reported in version 3.12.)
2. java 17
3. DevEco-Studio / command-line-tools , 5.0.3.300+
   1. ohpm, hvigorw, node, and OpenHarmony SDK are included.
4. Xcode14.3

## Generating flutter.har file

1. After the engine product is built, the **flutter.har** file (src/out/ohos_debug_unopt_arm64/flutter.har) is generated.
2. Build the HAP file after copying the **libflutter.so** file (and **libvmservice_snapshot.so** file if in the profile mode) to the **flutter_embedding/flutter/ohos** directory. For details, see [Flutter Engine](https://gitcode.com/openharmony-tpc/flutter_engine/blob/master/README.en.md).

## Debugging the Flutter Engine Using DevEco Studio

Reference:

[Debugging-the-engine](https://github.com/flutter/engine/blob/main/docs/Debugging-the-engine.md)

<!--no_check-->