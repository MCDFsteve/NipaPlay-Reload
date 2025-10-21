# Flutter OpenHarmony化工程的目录结构

## Flutter OpenHarmony化工程关键文件

1. 配置文件
   1. ohos/AppScope/app.json5, project配置文件, 应用的全局配置信息，包含应用的包名、开发厂商、版本号等基本信息。
   2. ohos/build-profile.json5, project配置文件
   3. ohos/oh-package.json5, project配置文件
   4. ohos/entry/build-profile.json5, module配置文件
   5. ohos/entry/oh-package.json5, module配置文件
   6. ohos/entry/src/main/module.json5, module配置文件, Module的基本配置信息，例如Module名称、类型、描述、支持的设备类型等基本信息。
2. 代码文件
   1. ohos/entry/src/main/entryability/EntryAbility.ets, 应用入口文件
   2. ohos/entry/src/main/pages/Index.ets, 应用加载的第一个页面

## 已过时，可删除的目录或文件

1. ohos/har/har_product/* , 直接从 flutter_flutter 的模板中复制
2. ohos/har/flutter_embedding.har , 替换为 ohos/har/flutter.har
3. ohos/dta/icudtl,dat , 直接从 flutter_flutter 的模板中复制
