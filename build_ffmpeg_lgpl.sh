#!/bin/bash

set -e

BUILD_DIR="$HOME/ffmpeg_build_lgpl"
INSTALL_DIR="$HOME/ffmpeg-lgpl"

rm -rf "$BUILD_DIR" "$INSTALL_DIR"
git clone https://git.ffmpeg.org/ffmpeg.git "$BUILD_DIR"

cd "$BUILD_DIR"

./configure \
  --prefix="$INSTALL_DIR" \
  --enable-shared \
  --disable-static \
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-gpl \
  --enable-version3

make -j$(sysctl -n hw.ncpu)
make install

echo "✅ FFmpeg LGPL 빌드 완료!"
echo "📁 위치: $INSTALL_DIR/bin/ffmpeg"

cp "$INSTALL_DIR/bin/ffmpeg" "/Users/ihuijae/Desktop/PythonWorkspace/bestcut/assets/ffmpeg/macos/ffmpeg"