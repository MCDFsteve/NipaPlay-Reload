# 更新Flutter插件项目结构

## 更新内容

- flutter插件项目中的ohos目录，将从OpenHarmony工程project结构，替换为OpenHarmony工程module结构。
- flutter工程中引用的har文件，统一放到 ohos/har 目录下。
- 更新后需要删除ohos插件中的旧模块目录。

## 更新步骤

以 [flutter_flutter](https://gitcode.com/openharmony-sig/flutter_flutter) 中的 integration_test 为例的更新步骤如下:

### 1. integration_test/ohos 目录由 project 结构修改为 module 结构

> 💡 注意：以下命令默认在类 Unix 环境（Linux/macOS）下运行。Windows 用户请使用 WSL 或自行适配 PowerShell 命令。

```sh
cd flutter_flutter/packages/integration_test
mv ohos/ohos ./ohos2
rm -rf ohos
mv ohos2 ohos
cd example
flutter pub get
flutter build hap --debug
```

执行`flutter run`后会出现报错，需要修改配置文件中的name字段，还需要修改 hvigorfile.ts。

### 2. 代码更新

#### 2.1 修改 integration_test/ohos/oh-package.json5

修改前：

```json
{
  "name": "ohos",
  "version": "1.0.0",
  "description": "Please describe the basic information.",
  "main": "",
  "author": "",
  "license": "",
  "dependencies": {
  },
  "devDependencies": {
    "@ohos/hypium": "1.0.11"
  }
}
```

修改后：

```json
{
  "name": "integration_test", // 和插件名(pubspec.yaml中的name)保持一致
  "version": "1.0.0",
  "description": "Please describe the basic information.",
  "main": "",
  "author": "",
  "license": "Apache-2.0",
  "dependencies": {
    "@ohos/flutter_ohos": "file:har/flutter.har",
  }
}
```

#### 2.2 修改 integration_test/ohos/src/main/module.json5

修改前：

```json
{
  "module": {
    "name": "ohos",
    "type": "har",
    "deviceTypes": [
      "default",
      "tablet",
      "2in1"
    ]
  }
}
```

修改后：

```json
{
  "module": {
    "name": "integration_test", // 和插件名(pubspec.yaml中的name)保持一致
    "type": "har",
    "deviceTypes": [
      "default",
      "tablet",
      "2in1"
    ]
  }
}
```

#### 2.3 修改 integration_test/ohos/hvigorfile.ts

修改前：

```json
import { appTasks } from '@ohos/hvigor-ohos-plugin';

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[]         /* Custom plugin to extend the functionality of Hvigor. */
}
```

修改后：

```json
export { harTasks } from '@ohos/hvigor-ohos-plugin';
```

## 检查是否可以正常运行

1. 使用 DevEco-Studio 打开 integration_test/example, 配置签名。
2. 使用命令运行example。

```
cd integration_test/example
flutter run -d $DEVICE --debug
```

### 运行OpenHarmony应用时，需要注意配置文件中 har文件 的引用

引用的har文件在 ohos/har 目录下。


#### integration_test/example/ohos/oh-package.json5

修改后：

```json
{
  // ...
  "dependencies": {
    "@ohos/flutter_ohos": "file:./har/flutter.har"
  },
  "overrides": {
    "@ohos/flutter_ohos": "file:./har/flutter.har"
  }
}
```

#### integration_test/example/ohos/entry/oh-package.json5

修改前

```json
{
  // ...
  "dependencies": {
    "@ohos/integration_test": "file:./har/integration_test.har",
  }
}
```

修改后

```json
{
  // ...
  "dependencies": {
    "integration_test": "file:../har/integration_test.har",
  }
}
```

## 可能遇到的问题

### 1. no such file or directory

日志信息：

```log
hvigor ERROR: ENOENT: no such file or directory, stat 'xxx/flutter_flutter/packages/integration_test/ohos/build/default/cache/default/default@packageHar/ohos/oh_modules/@ohos/flutter_ohos'
```

![](../media/09/error1.jpg)

解决方案：

手动删除报错信息提示的文件。

### 2. operation not permitted, symlink

日志信息：

```log
hvigor ERROR: ENOENT: operation not permitted, symlink
'xxx/webview_flutter_ohos/ohos/webview_flutter/oh_modules/.ohpm/@ohos+flutter_ohos@file+libs+flutter.har/oh_modules/@ohos/flutter_ohos' -> 
'xxx/webview_flutter_ohos/ohos/build/default/cache/default/default@PackageHar/webview_flutter/oh_modules/@ohos/flutter_ohos'
```

解决方案：

har结构整改前的部分目录，在更新代码后需要手动删除，例如

1. flutter_packages/packages/webview_flutter_ohos/ohos/webview_flutter
2. flutter_packages/packages/path_provider_ohos/ohos/path_provider
3. flutter_packages/packages/file_selector_ohos/ohos/FileSelector