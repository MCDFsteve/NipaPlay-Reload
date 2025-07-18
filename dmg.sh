#!/bin/bash

version=$(head -n 19 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)
dmg_name="NipaPlay_${version}_macOS_Universal.dmg"

# Create a temporary directory for the DMG layout
temp_dir=$(mktemp -d)
mkdir -p "${temp_dir}/.background"

# Copy the app to the temporary directory
cp -R "build/macos/Build/Products/Release/NipaPlay.app" "${temp_dir}/"

# Create a symbolic link to Applications
ln -s /Applications "${temp_dir}/Applications"

# Create the background image with arrow
convert -size 800x450 xc:white \
  -font Arial -pointsize 100 -fill '#333333' \
  -draw "text 400,225 '>'" \
  "${temp_dir}/.background/background.png"

# Verify background image was created
if [ ! -f "${temp_dir}/.background/background.png" ]; then
  echo "Error: Background image was not created"
  exit 1
fi

echo "Attempting to create DMG with custom layout..."

# Create the DMG with CI-friendly options
create-dmg \
  --volname "NipaPlay-${version}" \
  --window-pos 200 120 \
  --window-size 800 450 \
  --icon-size 100 \
  --icon "NipaPlay.app" 200 185 \
  --icon "Applications" 600 185 \
  --background "${temp_dir}/.background/background.png" \
  --no-internet-enable \
  --skip-jenkins \
  --timeout 120 \
  "${dmg_name}" \
  "${temp_dir}"

# Check if DMG creation was successful
if [ ! -f "${dmg_name}" ]; then
  echo "Primary DMG creation failed, trying simplified approach..."
  
  # Clean up any partial files
  rm -f "${dmg_name}"
  
  # Simple DMG creation without complex AppleScript operations
  create-dmg \
    --volname "NipaPlay-${version}" \
    --window-size 800 450 \
    --icon-size 100 \
    --app-drop-link 600 185 \
    --no-internet-enable \
    --skip-jenkins \
    "${dmg_name}" \
    "build/macos/Build/Products/Release/NipaPlay.app"
fi

# Clean up
rm -rf "${temp_dir}"

# Verify DMG file exists
if [ ! -f "${dmg_name}" ]; then
  echo "Error: DMG file was not created at ${dmg_name}"
  exit 1
fi

echo "DMG file created successfully: ${dmg_name}"
ls -la "${dmg_name}"