# Directory Structure of the OpenHarmony Flutter Project

## Key Files of the OpenHarmony Flutter Project

1. Configuration files
   1. **ohos/AppScope/app.json5**, a project configuration file, contains the global configuration information of the application, including the bundle name, vendor, and version number of the application.
   2. **ohos/build-profile.json5**, a project configuration file.
   3. **ohos/oh-package.json5**, a project configuration file.
   4. **ohos/entry/build-profile.json5**, a module configuration file.
   5. **ohos/entry/oh-package.json5**, a module configuration file.
   6. **ohos/entry/src/main/module.json5**, a module configuration file, contains the basic configuration information of a module, including the module name, type, description, and supported device types.
2. Code files
   1. **ohos/entry/src/main/entryability/EntryAbility.ets**, an entry file of the application.
   2. **ohos/entry/src/main/pages/Index.ets**, the first page loaded by the application.

## Outdated Directories or Files to Be Deleted

1. **ohos/har/har_product/***, copied from the **flutter_flutter** template.
2. **ohos/har/flutter_embedding.har**, replaced by **ohos/har/flutter.har**.
3. **ohos/dta/icudtl.dat**, copied from the **flutter_flutter** template.
