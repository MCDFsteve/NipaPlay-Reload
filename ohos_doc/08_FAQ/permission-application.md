# Permission Application Related Issues

Solutions:

1. The application must declare permissions under the `requestPermissions` tag in the `module.json5` configuration file. After configuring the permissions, re-sign the application.

2. Permissions can be temporarily granted during signing. For formal usage, [apply for related permissions via email](https://developer.huawei.com/consumer/en/doc/app/agc-help-add-releaseprofile-0000001914714796).

## Flutter Input Field Long-Press Cannot Paste Issue

The application needs to request clipboard permission: `ohos.permission.READ_PASTEBOARD`.

```
    "requestPermissions": [
      {
        "name": "ohos.permission.READ_PASTEBOARD",
        "reason": "$string:EntryAbility_desc",
        "usedScene": {
          "abilities": [
            "EntryAbility"
          ],
          "when": "inuse"
        }
      }
    ]
```

## Flutter Cannot Save Image to Album Issue

The application needs to request permission to save images: `ohos.permission.WRITE_IMAGEVIDEO`.

```
    "requestPermissions": [
      {
        "name": "ohos.permission.WRITE_IMAGEVIDEO",
        "reason": "$string:EntryAbility_desc",
        "usedScene": {
          "abilities": [
            "EntryAbility"
          ],
          "when": "inuse"
        }
      }
    ]
```
