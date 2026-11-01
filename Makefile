# Makefile biên dịch chuẩn với cờ -isysroot của Xcode iOS SDK
SDK_PATH := $(shell xcrun --sdk iphoneos --show-sdk-path)

all:
	xcrun --sdk iphoneos clang -isysroot "$(SDK_PATH)" \
		-arch arm64 -dynamiclib -fobjc-arc -std=gnu99 \
		-mios-version-min=14.0 \
		-Wno-deprecated-declarations \
		-install_name @rpath/BlockBlastAutoBot.dylib \
		-framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
		Tweak.m -o BlockBlastAutoBot.dylib
	codesign -f -s - BlockBlastAutoBot.dylib
