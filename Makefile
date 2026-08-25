VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo dev)
PKG = xeneon-edge-touch-macos-$(VERSION)
APP = Xeneon Touch
APPDIR = dist/$(APP).app
SRC = Driver.swift

# ---- command-line driver -------------------------------------------------

touchd: $(SRC) main.swift
	swiftc -O -o touchd $(SRC) main.swift

touchd-universal: $(SRC) main.swift
	swiftc -O -target arm64-apple-macos12 -o touchd-arm64 $(SRC) main.swift
	swiftc -O -target x86_64-apple-macos12 -o touchd-x86_64 $(SRC) main.swift
	lipo -create -output touchd touchd-arm64 touchd-x86_64
	rm -f touchd-arm64 touchd-x86_64

package: touchd-universal
	rm -rf dist/$(PKG) && mkdir -p dist/$(PKG)
	cp touchd com.morgan.touchd.plist install.sh uninstall.sh README.md LICENSE dist/$(PKG)/
	tar -C dist -czf dist/$(PKG).tar.gz $(PKG)
	cd dist && shasum -a 256 $(PKG).tar.gz > $(PKG).tar.gz.sha256
	@echo "-> dist/$(PKG).tar.gz"

# ---- menu-bar app --------------------------------------------------------

app: $(SRC) App/XeneonTouchApp.swift App/Info.plist
	rm -rf "$(APPDIR)" && mkdir -p "$(APPDIR)/Contents/MacOS"
	swiftc -O -parse-as-library -target arm64-apple-macos13 -o "app-arm64" $(SRC) App/XeneonTouchApp.swift
	swiftc -O -parse-as-library -target x86_64-apple-macos13 -o "app-x86_64" $(SRC) App/XeneonTouchApp.swift
	lipo -create -output "$(APPDIR)/Contents/MacOS/$(APP)" app-arm64 app-x86_64
	rm -f app-arm64 app-x86_64
	cp App/Info.plist "$(APPDIR)/Contents/"
	codesign --force --sign - --identifier com.morganz.xeneon-touch "$(APPDIR)"
	@echo "-> $(APPDIR)"

dmg: app
	rm -rf dist/dmg dist/$(APP)-$(VERSION).dmg && mkdir -p dist/dmg
	cp -R "$(APPDIR)" dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -quiet -volname "$(APP)" -srcfolder dist/dmg -ov -format UDZO "dist/$(APP)-$(VERSION).dmg"
	rm -rf dist/dmg
	cd dist && shasum -a 256 "$(APP)-$(VERSION).dmg" > "$(APP)-$(VERSION).dmg.sha256"
	@echo "-> dist/$(APP)-$(VERSION).dmg"

clean:
	rm -rf touchd touchd-arm64 touchd-x86_64 app-arm64 app-x86_64 dist

.PHONY: touchd-universal package app dmg clean
