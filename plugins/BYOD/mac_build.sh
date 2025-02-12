#!/bin/bash

set -e

DIR=$(dirname "${BASH_SOURCE[0]}")
SDK_PATH="$(pwd)/SDKs"

# clone git repo
name=$(jq -r '.name' "$DIR/metadata.json")
repo=$(jq -r '.repo' "$DIR/metadata.json")
hash=$(jq -r '.hash' "$DIR/metadata.json")
echo "Pulling $name from $repo at commit $hash"

git clone "$repo" "$name"
cd "$name"
git checkout "$hash"
git submodule update --init --recursive

# Clone add-on modules
#USERNAME="jatinchowdhury18"
#PASSWORD="$OUR_GITHUB_PAT"
#add_ons_repo="https://github.com/Chowdhury-DSP/BYOD-add-ons"

#add_ons_repo_with_pass="${add_ons_repo:0:8}$USERNAME:$PASSWORD@${add_ons_repo:8}"
#git clone $add_ons_repo_with_pass modules/BYOD-add-ons

# set up SDK paths
#sed -i -e "s~# juce_set_vst2_sdk_path.*~juce_set_vst2_sdk_path(${SDK_PATH}/VST2_SDK)~" CMakeLists.txt

# build Win64
cmake -Bbuild -GXcode -DBYOD_BUILD_ADD_ON_MODULES=ON -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="Developer ID Application" \
    -DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM="$TEAM_ID" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_STYLE="Manual" \
    -D"CMAKE_OSX_ARCHITECTURES=arm64;x86_64" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    -DCMAKE_XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -DBUILD_RELEASE=ON
cmake --build build --config Release --parallel 4 | xcpretty

# copy builds to bin
echo "Copying builds..."
mkdir -p bin/Mac

cp -R "build/${name}_artefacts/Release/Standalone/${name}.app" "bin/Mac/${name}.app"
cp -R "build/${name}_artefacts/Release/VST/${name}.vst" "bin/Mac/${name}.vst"
cp -R "build/${name}_artefacts/Release/VST3/${name}.vst3" "bin/Mac/${name}.vst3"
cp -R "build/${name}_artefacts/Release/CLAP/${name}.clap" "bin/Mac/${name}.clap"
cp -R "build/${name}_artefacts/Release/AU/${name}.component" "bin/Mac/${name}.component"
#echo y | pscp -pw "$CCRMA_PASS" -r jatin@ccrma-gate.stanford.edu:/user/j/jatin/aax_builds/Mac/${name}.aaxplugin "bin/Mac/${name}.aaxplugin"

# create installer
echo "Creating installer..."
script_file=installers/mac/BYOD.pkgproj

version=$(cut -f 2 -d '=' <<< "$(grep 'CMAKE_PROJECT_VERSION:STATIC' build/CMakeCache.txt)")
echo "Setting app version: $version..."
sed -i '' "s/##APPVERSION##/${version}/g" $script_file
sed -i '' "s/##APPVERSION##/${version}/g" installers/mac/Intro.txt

echo "Copying License..."
cp LICENSE Installers/mac/LICENSE.txt

# build installer
echo Building...
packagesbuild $script_file

# sign the installer package
echo "Signing installer package..."
pkg_dir=BYOD_Installer_Packaged
mkdir $pkg_dir
productsign -s "$TEAM_ID" build/BYOD.pkg $pkg_dir/BYOD-signed.pkg

echo "Notarizing installer package..."
npx notarize-cli --file $pkg_dir/BYOD-signed.pkg \
    --bundle-id com.smallbutfine.BYOD \
    --username martin.haverland@gmx.de \
    --password "$INSTALLER_PASS" \
    --asc-provider "$TEAM_ID"

echo "Building disk image..."
vol_name=BYOD-Mac-$version
hdiutil create "$vol_name.dmg" -fs HFS+ -srcfolder $pkg_dir -format UDZO -volname "$vol_name"

# copy installer to products
cp "$vol_name.dmg" ../products/
