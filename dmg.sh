version=$(head -n 19 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)

flutter build macos --release \
&& brew install create-dmg \
&& create-dmg --volname NipaPlay-${version} --window-pos 200 120 --window-size 800 450 --icon-size 100 --app-drop-link 600 185 NipaPlay-${version}.dmg build/macos/Build/Products/Release/NipaPlay.app