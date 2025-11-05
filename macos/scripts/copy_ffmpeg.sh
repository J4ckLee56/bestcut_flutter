#!/bin/bash

# FFmpeg 복사 스크립트
# 빌드 시 자동으로 FFmpeg를 앱 번들에 복사

set -e

echo "🎬 FFmpeg 복사 시작..."

# 프로젝트 루트 디렉토리 (macos 폴더의 상위)
PROJECT_ROOT="${SRCROOT}/.."

# 소스 경로
SOURCE_DIR="${PROJECT_ROOT}/ffmpeg/macos"
# 목적지 경로 (앱 번들의 Resources 폴더)
DEST_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"

echo "📍 프로젝트 루트: $PROJECT_ROOT"
echo "📍 FFmpeg 소스: $SOURCE_DIR"
echo "📍 목적지: $DEST_DIR"

# FFmpeg 디렉토리가 존재하는지 확인
if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ 오류: FFmpeg 디렉토리를 찾을 수 없습니다: $SOURCE_DIR"
    exit 1
fi

# Resources 디렉토리 생성 (없으면)
mkdir -p "$DEST_DIR"

# FFmpeg 실행 파일 복사
echo "📦 FFmpeg 실행 파일 복사 중..."
cp "$SOURCE_DIR/ffmpeg" "$DEST_DIR/ffmpeg"
chmod +x "$DEST_DIR/ffmpeg"

# 라이브러리 파일들 복사 (.dylib)
echo "📦 FFmpeg 라이브러리 복사 중..."
if ls "$SOURCE_DIR"/*.dylib 1> /dev/null 2>&1; then
    cp "$SOURCE_DIR"/*.dylib "$DEST_DIR/"
    chmod +x "$DEST_DIR"/*.dylib
    echo "✅ 라이브러리 복사 완료"
else
    echo "⚠️  .dylib 파일이 없습니다 (무시해도 됨)"
fi

echo "✅ FFmpeg 복사 완료!"
echo "   - 소스: $SOURCE_DIR"
echo "   - 목적지: $DEST_DIR"

