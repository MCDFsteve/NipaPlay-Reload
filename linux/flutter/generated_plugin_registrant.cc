//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <charset_converter/charset_converter_plugin.h>
#include <desktop_drop/desktop_drop_plugin.h>
#include <file_selector_linux/file_selector_plugin.h>
#include <fvp/fvp_plugin.h>
#include <hotkey_manager_linux/hotkey_manager_linux_plugin.h>
#include <media_kit_libs_linux/media_kit_libs_linux_plugin.h>
#include <media_kit_video/media_kit_video_plugin.h>
#include <screen_retriever_linux/screen_retriever_linux_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>
#include <volume_controller/volume_controller_plugin.h>
#include <window_manager/window_manager_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) charset_converter_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "CharsetConverterPlugin");
  charset_converter_plugin_register_with_registrar(charset_converter_registrar);
  g_autoptr(FlPluginRegistrar) desktop_drop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DesktopDropPlugin");
  desktop_drop_plugin_register_with_registrar(desktop_drop_registrar);
  g_autoptr(FlPluginRegistrar) file_selector_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FileSelectorPlugin");
  file_selector_plugin_register_with_registrar(file_selector_linux_registrar);
  g_autoptr(FlPluginRegistrar) fvp_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FvpPlugin");
  fvp_plugin_register_with_registrar(fvp_registrar);
  g_autoptr(FlPluginRegistrar) hotkey_manager_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "HotkeyManagerLinuxPlugin");
  hotkey_manager_linux_plugin_register_with_registrar(hotkey_manager_linux_registrar);
  g_autoptr(FlPluginRegistrar) media_kit_libs_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MediaKitLibsLinuxPlugin");
  media_kit_libs_linux_plugin_register_with_registrar(media_kit_libs_linux_registrar);
  g_autoptr(FlPluginRegistrar) media_kit_video_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MediaKitVideoPlugin");
  media_kit_video_plugin_register_with_registrar(media_kit_video_registrar);
  g_autoptr(FlPluginRegistrar) screen_retriever_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ScreenRetrieverLinuxPlugin");
  screen_retriever_linux_plugin_register_with_registrar(screen_retriever_linux_registrar);
  g_autoptr(FlPluginRegistrar) url_launcher_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url_launcher_linux_registrar);
  g_autoptr(FlPluginRegistrar) volume_controller_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "VolumeControllerPlugin");
  volume_controller_plugin_register_with_registrar(volume_controller_registrar);
  g_autoptr(FlPluginRegistrar) window_manager_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "WindowManagerPlugin");
  window_manager_plugin_register_with_registrar(window_manager_registrar);
}
