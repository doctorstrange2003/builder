#!/bin/bash

# ========================
# Android Kernel Build Script (DAVINCI ONLY)
# ========================

# Colors
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[1;33m'
white='\033[0m'

echo -e "$green[+] Cleaning up previous builds...$white"
rm -rf out zip error.log

# Device Config (DAVINCI ONLY)
DEVICE_TYPE="${DEVICE_TYPE:-davinci}"

if [ "$DEVICE_TYPE" != "davinci" ]; then
  echo -e "$red[!] Only 'davinci' is supported. Set DEVICE_TYPE=davinci$white"
  exit 1
fi

DEVICE="REDMI K20 (OSS)"
KERNEL_NAME="SLEEPY_KERNEL-OSS"
CODENAME="DAVINCI"
DEFCONFIG_COMMON="vendor/sdmsteppe-perf_defconfig"
DEFCONFIG_DEVICE="vendor/davinci.config"
AnyKernel="https://github.com/itsshashanksp/AnyKernel3.git"
AnyKernelbranch="davinci"

# Host + User Info
HOSST="sleeping-bag"
USEER="itsshashanksp"
KRNL_REL_TAG="${KERNEL_TAG:-test}"

# Telegram Bot Setup
BOT_MSG_URL="https://api.telegram.org/bot$API_BOT/sendMessage"
BOT_BUILD_URL="https://api.telegram.org/bot$API_BOT/sendDocument"

tg_post_msg() {
  curl -s -X POST "$BOT_MSG_URL" -d chat_id="$2" \
    -d "parse_mode=html" \
    -d text="$1"
}

tg_post_build() {
  MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)
  curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
    -F chat_id="$2" \
    -F parse_mode=html \
    -F caption="$3 build completed in $(($Diff / 60))m $(($Diff % 60))s | <b>MD5</b>: <code>$MD5CHECK</code>"
}

tg_error() {
  curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
    -F chat_id="$2" \
    -F parse_mode=html \
    -F caption="Build failed, check <code>error.log</code>"
}

# Clone Clang
echo -e "$green[+] Cloning Clang...$white"
git clone --depth=1 https://gitlab.com/itsshashanksp/android_prebuilts_clang_host_linux-x86_clang-r547379.git "$HOME/clang"

export PATH="$HOME/clang/bin:$PATH"
export KBUILD_COMPILER_STRING=$("$HOME/clang/bin/clang" --version | head -n 1)

# Build Environment
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_HOST="$HOSST"
export KBUILD_BUILD_USER="$USEER"
mkdir -p out

# Build Kernel
build_kernel() {
  Start=$(date +%s)
  make clean && make mrproper
  make "$DEFCONFIG_COMMON" O=out
  make "$DEFCONFIG_DEVICE" O=out

  make -j$(nproc) O=out \
    ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi- 2>&1 | tee error.log

  End=$(date +%s)
  Diff=$(($End - $Start))
}

echo -e "$yellow[•] Starting build for $DEVICE ($CODENAME)...$white"
tg_post_msg "🔨 Building $KERNEL_NAME for $DEVICE ($CODENAME)" "$CHATID"
build_kernel || error=true

IMG="out/arch/arm64/boot/Image.gz"
DTBO="out/arch/arm64/boot/dtbo.img"
DTB="out/arch/arm64/boot/dtb.img"

if [ ! -f "$IMG" ]; then
  echo -e "$red[✗] Build failed. See error.log$white"
  tg_post_msg "❌ Kernel build failed" "$CHATID"
  tg_error "error.log" "$CHATID"
  exit 1
fi

# Zip kernel
echo -e "$green[✓] Build succeeded. Cloning AnyKernel...$white"
git clone --depth=1 "$AnyKernel" -b "$AnyKernelbranch" zip
cp "$IMG" "$DTBO" "$DTB" zip/

cd zip || exit
ZIPNAME="$KERNEL_NAME-$KRNL_REL_TAG-$CODENAME"
zip -r9 "$ZIPNAME" * -x .git README.md LICENSE *placeholder
curl -sLo zipsigner-3.0.jar https://gitlab.com/itsshashanksp/zipsigner/-/raw/master/bin/zipsigner-3.0-dexed.jar
java -jar zipsigner-3.0.jar "$ZIPNAME".zip "$ZIPNAME"-signed.zip

tg_post_msg "✅ Build successful! Uploading ZIP..." "$CHATID"
tg_post_build "$ZIPNAME"-signed.zip "$CHATID"
tg_post_msg "🎉 All done!" "$CHATID"

# Cleanup
cd ..
rm -rf out zip error.log zipsigner-3.0.jar
