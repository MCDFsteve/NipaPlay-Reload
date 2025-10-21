### Document Naming (Delete)

> If there is an ohos folder under the original warehouse, it is necessary to add or replace README.md and README_CN.md under the ohos folder
>
> If there is no ohos folder under the original warehouse, it is necessary to create README-OpenHarmony.md and README-OpenHarmony_CN.md at the same level as the original README.md

> Add ohos instructions and corresponding links in the original READ.md document, and add your own document links in appropriate locations:
>
> (Example):
>
> ```bash
> ### OpenHarmony
> 
> - [中文](../camera_ohos/README_CN.md)
> - [EN](../camera_ohos/README.md)
> ```
>

<p align="center">
  <h1 align="center"> <code>< npm package name of the source repository ></code> </h1>
</p>



> This project is based on [Github Or a pub address](https://github.com/< HarmonyOS 化源码仓地址>)

如：

> This project is based on [webview_flutter@4.6.0](https://pub.dev/packages/webview_flutter/versions/4.6.0) （Delete）

##  Installation and Usage

For example, enter the project directory and add the following dependencies in pubspec.yaml:

<!-- tabs:start -->

#### **npm**

```bash
npm install @flutter-tpl/<库名>@file:#
```

#### pubspec.yaml

```bash
dependencies:
  image_picker:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/image_picker
```

Execute Command

```bash
flutter pub get
```

<!-- tabs:end -->

### RUN

Execute on the terminal:

```bash
flutter run -d xxxxxxxx
```

Then compile and run it.

### Use case

For detailed usage cases, please refer to [ohos/example](./example)

## Constraints

### compatibility

**Library that has already released releases**（deleted）

To use this library, you need to use the correct Flutter. In addition, the matching DevEco Studio and mobile ROM are also required.

**Unreleased releases using the original library**（deleted）

The content of this document has been validated based on the following versions:

(Example)

1. RNOH: 0.72.27; SDK: HarmonyOS-Next-DB1 5.0.0.29(SP1); IDE: DevEco Studio 5.0.3.403; ROM: 3.0.0.25;

### Permission requirements (if any)

(Fill in the relevant permission configuration)

**The following properties, static methods, and APIs need to be checked in the description of the mobile platform. For example, if the HarmonyOS interface is already supported and iOS and Android are mentioned in the description, it is necessary to check if Harmony has been added to the description. Example as follows (deleted)**

（Example）The following permissions include the `system_basic` permission, but the default application permission is `normal`. Only the `normal` permission can be used. Therefore, the error **9568289** may be reported during the installation of the HAP package. For details, see [Document](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/bm-tool-V5#EN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed) Change the application level to `system_basic`.

```
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when":"inuse"
    }
  },
]
```

（删除）

**Add the reason for applying for the above permissions in the entry directory**

open `entry/src/main/resources/base/element/string.json`，add：

```
{
  "string": [
    {
      "name": "network_reason",
      "value": "使用网络"
    },
  ]
}
```

##  Static Methods (If Any)

> [!TIP] If the value of **HarmonyOS Support** is **yes**, it means that the HarmonyOS platform supports this property; **no** means the opposite; **partially** means some capabilities of this property are supported. The usage method is the same on different platforms and the effect is the same as that of iOS or Android.

| Name | Description | Type | HarmonyOS Support  |
| ---- | ----------- | ---- | ------------------ |
| XXX  | XXX         | XXX  | (yes/no/partially) |

##  APIs (TurboModules, If Any)

> [!TIP] "HarmonyOS Support"列为 yes 表示 HarmonyOS 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name | Description | Type | HarmonyOS Support  |
| ---- | ----------- | ---- | ------------------ |
| XXX  | XXX         | XXX  | (yes/no/partially) |

##  Properties (If Any)

> [!TIP] If the value of **HarmonyOS Support** is **yes**, it means that the HarmonyOS platform supports this property; **no** means the opposite; **partially** means some capabilities of this property are supported. The usage method is the same on different platforms and the effect is the same as that of iOS or Android.

| Name | Description | Type | HarmonyOS Support  |
| ---- | ----------- | ---- | ------------------ |
| XXX  | XXX         | XXX  | (yes/no/partially) |

##  Known Issues

- [ ] xxx issue: [issue#***]([https://github.com/issue](https://gitee.com/link?target=https%3A%2F%2Fgithub.com%2Fissue) address 1)
- [ ]  yyy issue: [issue#***]([https://github.com/issue](https://gitee.com/link?target=https%3A%2F%2Fgithub.com%2Fissue) address 2)

##  Others

##  License

This project is licensed under [XXX License (XXX)](https://gitee.com/link?target=https%3A%2F%2Fgithub.com%2Fxxx%2Fxxx%2Fblob%2Fmain%2FLICENSE.md).

Example: This project is licensed under [MIT License](https://gitcode.com/openharmony-tpc/flutter_packages/blob/master/packages/webview_flutter/webview_flutter/LICENSE). (Delete)



> #  Document Template (Delete)
>
> > [!ATTENTION] When using this template, delete the statements that end with "(Delete)", and modify the content enclosed by angle brackets (<>). (Delete)
>
> > Template version: v0.0.1