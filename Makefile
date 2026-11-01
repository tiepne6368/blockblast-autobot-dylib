# Makefile biên dịch nhanh bằng Xcode iOS SDK
all:
	xcrun -sdk iphoneos clang++ -arch arm64 -dynamiclib -std=c++17 -fobjc-arc \
		-mios-version-min=14.0 \
		-install_name @executable_path/Frameworks/BlockBlastAutoBot.dylib \
		-framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
		Tweak.mm -o BlockBlastAutoBot.dylib
	ldid -S BlockBlastAutoBot.dylib
