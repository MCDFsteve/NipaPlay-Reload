# ohos平台适配flutter三方库指导

## 1. 准备工作

flutter开发环境已配置：[参考](https://gitcode.com/openharmony-sig/flutter_flutter/blob/master/README.md)

下载待适配的三方插件：[官方插件库](https://pub.dev/)

本指导书，
以适配 [path_provider 2.1.0](https://pub-web.flutter-io.cn/packages/path_provider/versions/2.1.0) 为例

## 2. 插件目录

![image-20240410105254011](../media/07_1/01_Plugin_Directory.png)

lib：是对接dart端代码的入口，由此文件接收到参数后，通过channel将数据发送到原生端；

android：安卓端代码实现目录；

ios：ios原生端实现目录；

example：一个依赖于该插件的Flutter应用程序，来说明如何使用它；

README.md：介绍包的文件；

CHANGELOG.md：记录每个版本中的更改；

LICENSE：包含软件包许可条款的文件。

## 3. 创建插件的ohos模块

命令：`flutter create --platforms ohos,android,ios --org <org> <appName>`

步骤：

1. 用Android Studio打开刚刚下载好的插件。

2. 打开Terminal，cd到插件目录下。

3. 执行命令`flutter create --platforms ohos path_provider_ohos` 创建一个ohos平台的flutter模块。

   执行创建命令前：

   ![image-20240410105254011](../media/07_1/02_Flutter_plugin_structure.png)

   执行创建命令后，可以将path_provider_ohos目录下的.dart_tool和.ldea文件删除。

   ![image-20240410105254011](../media/07_1/03_OpenHarmony_plugin_structure.png)

## 4. 编写ohos插件的dart接口和pubspec.yaml文件

可直接复制path_provider_android目录下lib的dart代码和pubspec.yaml文件进行修改。

dart代码基本不需要修改，只需要将android字样改为ohos。

lib目录dart代码：

![image-20240410105254011](../media/07_1/04_ohos_plugin_dart_side_structure.png)

pubspec.yaml文件：

```
# 仅做参考
name: path_provider_ohos
description: Ohos implementation of the path_provider plugin.
repository: https://gitcode.com/openharmony-tpc/flutter_packages/tree/master/packages/path_provider/path_provider_ohos
issue_tracker: https://gitcode.com/openharmony-tpc/flutter_packages/issues
version: 2.2.1

environment:
  sdk: ">=2.18.0 <4.0.0"
  flutter: ">=3.3.0"

flutter:
  plugin:
    implements: path_provider
    platforms:
      ohos:
        package: io.flutter.plugins.pathprovider
        pluginClass: PathProviderPlugin
        dartPluginClass: PathProviderOhos

dependencies:
  flutter:
    sdk: flutter
  path_provider_platform_interface: ^2.0.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  pigeon: ^9.2.4
  test: ^1.16.0
```

## 5. 编写ohos插件的原生ets模块

### 5.1 创建ohos的插件模块

由于是写ohos平台的flutter插件，而不是写一个应用,需要将原来的entry模块删除，新建一个path_provider插件的静态模块，用来写ets原生代码逻辑。

步骤：

1. 用DevEco Studio打开path_provider_ohos下的ohos项目：

   ![image-20240410105254011](../media/07_1/05_The_ohos_project_in_the_OpenHarmony_plugin.png)

2. 新建一个名称为path_provider的静态模块：

   在DevEco Studio左上角点击`Flie > New > Module > Static Library > Next`，module name填写为`path_provider`,其他选项为默认，点击Finish，完成创建。

   ![image-20240410105254011](../media/07_1/06_Create_new_path_provider_module.png)

3. 删除entry以及其他多余目录：

   entry目录（entry是用来写应用的，现在是要写插件，此处已不需要，应该删除），将`path_provider > src > main > ets`目录下的文件全部删除(此处是一些模板代码可删除)。

   ![image-20240410105254011](../media/07_1/07_Delete_entry_and_other_redundant_directories.png)

### 5.2 修改相关配置文件

1. 在path_provider目录内的oh-package.json5添加libs/flutter.har 依赖：

    ```
    {
      "name": "path_provider",
      "version": "1.0.0",
      "description": "Please describe the basic information.",
      "main": "Index.ets",
      "author": "",
      "license": "Apache-2.0",
      "dependencies": {
        "@ohos/flutter_ohos": "file:libs/flutter.har"  //此处为添加的依赖
      }
    }
    ```

2. 将path_provider目录外侧的oh-package.json5的dependencies中的flutter.har依赖删除：

    ```
    {
      "name": "path_provider_ohos",
      "version": "1.0.0",
      "description": "Please describe the basic information.",
      "main": "",
      "author": "",
      "license": "",
      "dependencies": {
      },
      "devDependencies": {
        "@ohos/hypium": "1.0.6"
      },
    }
    ```

3. 在path_provider目录下添加flutter.har：

    ![image-20240410105254011](../media/07_1/08_Add_flutter.har_file.png)

### 5.3 编写ets代码

文件结构，和代码逻辑可参考安卓或ios：https://gitcode.com/openharmony-tpc/flutter_packages/tree/master/packages/path_provider/path_provider_android

ohos的api可以参考：https://gitcode.com/openharmony/docs

![image-20240410105254011](../media/07_1/09_Write_ets_code.png)


### 5.4 修改index文件

```
# 仅作参考
import PathProviderPlugin from './src/main/ets/io/flutter/plugins/pathprovider/PathProviderPlugin'

export default PathProviderPlugin
```

### 5.5 打har

写完代码，改完配置文件后，即可打har包。

打包工具：DevEco Studio。

打包步骤：
1. 鼠标定位到path_provider目录。
2. 点击DevEco Studio中的Build。
3. 点击Make Module 'pathprovider'选项。
4. 等待打包完成。

![image-20240410105254011](../media/07_1/10_Steps_for_creating_har_packages_for_the_project.png)

预期结果：

在`path_provider > build > default > outputs `中有path_provider.har生成，即为打har包成功。

![image-20240410105254011](../media/07_1/11_Successfully_converted_to_har_package.png)

## 6. 编写example

### 6.1 创建一个ohos平台的flutter example应用,用来验证刚刚适配的插件功能

cd 到path_provider_ohos目录下 ；

命令：`flutter create --platforms ohos example`

工具：Android Studio

![image-20240410105254011](../media/07_1/12_Create_example_command.png)

![image-20240410105254011](../media/07_1/13_example.png)

### 6.2 修改dart代码

复制`path_provider_android\example\lib`下的main.dart代码，替换`path_provider_ohos\example\lib`下的main.dart代码。

### 6.3 修改example pubspec.yaml文件

```
#仅作参考
name: path_provider_example
description: Demonstrates how to use the path_provider plugin.
publish_to: none

environment:
  sdk: ">=2.18.0 <4.0.0"
  flutter: ">=3.3.0"

dependencies:
  flutter:
    sdk: flutter
  path_provider:
    path: ../../path_provider
  path_provider_platform_interface: ^2.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

flutter:
  uses-material-design: true
```

## 7. 修改path_provider的pubspec.yaml文件

flutter: plugin:platforms添加ohos。

dependencies:添加path_provider_ohos依赖。

```
name: path_provider
description: Flutter plugin for getting commonly used locations on host platform file systems, such as the temp and app data directories.
repository: https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider
issue_tracker: https://github.com/flutter/flutter/issues?q=is%3Aissue+is%3Aopen+label%3A%22p%3A+path_provider%22
version: 2.1.0

environment:
  sdk: ">=2.18.0 <4.0.0"
  flutter: ">=3.3.0"

flutter:
  plugin:
    platforms:
      android:
        default_package: path_provider_android
      ios:
        default_package: path_provider_foundation
      linux:
        default_package: path_provider_linux
      macos:
        default_package: path_provider_foundation
      windows:
        default_package: path_provider_windows
      ohos:
        default_package: path_provider_ohos   #此处为添加

dependencies:
  flutter:
    sdk: flutter
  path_provider_android: ^2.1.0
  path_provider_foundation: ^2.3.0
  path_provider_linux: ^2.2.0
  path_provider_platform_interface: ^2.1.0
  path_provider_windows: ^2.2.0
  path_provider_ohos:
    path: ../path_provider_ohos    #此处为添加

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  plugin_platform_interface: ^2.0.0
  test: ^1.16.0
```

## 8. 运行example

### 8.1 签名

用 `Deveco Studio` 打开三方库的 `example > ohos` 目录。

单击 `File > Project Structure > Project > Signing Configs` 界面勾选 `Automatically generate signature`，等待自动签名完成即可，单击 `OK`。

![image-20240410105254011](../media/07_1/14_Signature.png)

### 8.2 运行

cd到`path_provider_ohos\example > ohos`目录，使用下列指令运行：

```
flutter pub get
flutter run -d <device-id>
```

**运行成功效果如下：**

![image-20240410105254011](../media/07_1/15_Successful_effect.png)
