### 文档命名（删除）

> 若原有仓下面有ohos文件夹，需要在ohos文件夹下面新增或者替换README.md和README_CN.md
>
> 若原有仓下面没有ohos文件夹，需要在原有的README.md同级新建README.OpenHarmony.md和README.OpenHarmony_CN.md

> 在原有的READ.md文档中，增加ohos说明和对应的链接，在适当位置额外增加你的文档链接：
>
> （示例）：
>
> ```bash
> ### OpenHarmony
> 
> - [中文](../camera_ohos/README_CN.md)
> - [EN](../camera_ohos/README.md)
> ```
>

<p align="center">
  <h1 align="center"> <code><原库 npm 包名></code> </h1>
</p>


> 本项目基于 [Github 或者pub地址](https://github.com/< HarmonyOS 化源码仓地址>)

如：

> 本项目基于 [webview_flutter@4.6.0](https://pub.dev/packages/webview_flutter/versions/4.6.0) 开发。（删除）

## 安装与使用

如：进入到工程目录并在 pubspec.yaml 中添加以下依赖：

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

执行命令

```bash
flutter pub get
```

<!-- tabs:end -->

### 运行

在终端执行：

```bash
flutter run -d xxxxxxxx
```

然后编译、运行即可。

### 使用案例

使用案例详见 [ohos/example](./example)

## 约束与限制

### 兼容性

**已发 Releases 的库**（删除）

要使用此库，需要使用正确的 Flutter 。另外，还需要使用配套的 DevEco Studio 和 手机 ROM。

**未发 Releases 使用原库的库**（删除）

本文档内容基于以下版本验证通过：

(示例)

1. RNOH: 0.72.27; SDK: HarmonyOS-Next-DB1 5.0.0.29(SP1); IDE: DevEco Studio 5.0.3.403; ROM: 3.0.0.25;

### 权限要求（如有）

（填入相关权限配置）

**以下属性、静态方法、API 需要检查说明中手机平台描述，例如已支持 HarmonyOS 的接口并且说明中提到 ios 和 android，那么需要检查是否补充 harmony 进到描述中。示例如下（删除）**

（示例）以下权限中有`system_basic` 权限，而默认的应用权限是 `normal` ，只能使用 `normal` 等级的权限，所以可能会在安装hap包时报错**9568289**，请参考 [文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/bm-tool) 修改应用等级为 `system_basic`

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

**在 entry 目录下添加申请以上权限的原因**

打开 `entry/src/main/resources/base/element/string.json`，添加：

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

## 静态方法（如有）

> [!TIP] "HarmonyOS Support"列为 yes 表示 HarmonyOS 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name | Description | Type | HarmonyOS Support  |
| ---- | ----------- | ---- | ------------------ |
| XXX  | XXX         | XXX  | (yes/no/partially) |

## API（如有，一般是 TurboModules）

> [!TIP] "HarmonyOS Support"列为 yes 表示 HarmonyOS 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name | Description | Type | HarmonyOS Support  |
| ---- | ----------- | ---- | ------------------ |
| XXX  | XXX         | XXX  | (yes/no/partially) |

## 属性（如有）

> [!TIP] "HarmonyOS Support"列为 yes 表示 HarmonyOS 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name | Description | Type | HarmonyOS Support  |
| ---- | ----------- | ---- | ------------------ |
| XXX  | XXX         | XXX  | (yes/no/partially) |

## 遗留问题

- [ ] xxx 问题: [issue#\*\*\*](https://github.com/issue地址1)
- [ ] yyy 问题: [issue#\*\*\*](https://github.com/issue地址2)

## 其他

## 开源协议

本项目基于 [XXX License (XXX)](https://github.com/xxx/xxx/blob/main/LICENSE.md) ，请自由地享受和参与开源。

例子：本项目基于 [The MIT License (MIT)](https://gitcode.com/openharmony-tpc/flutter_packages/blob/master/packages/webview_flutter/webview_flutter/LICENSE) ，请自由地享受和参与开源。(删除)



# 文档模板(删除)

> [!ATTENTION] 使用模板时请将后面带有 (删除) 的语句删除。<>内是需要修改的内容。(删除)

> 模板版本：v0.0.1