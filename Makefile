VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo dev)
PKG = xeneon-edge-touch-macos-$(VERSION)

touchd: touchd.swift
	swiftc -O -o touchd touchd.swift

# Universal binary (Apple Silicon + Intel)
touchd-universal: touchd.swift
	swiftc -O -target arm64-apple-macos12 -o touchd-arm64 touchd.swift
	swiftc -O -target x86_64-apple-macos12 -o touchd-x86_64 touchd.swift
	lipo -create -output touchd touchd-arm64 touchd-x86_64
	rm -f touchd-arm64 touchd-x86_64

package: touchd-universal
	rm -rf dist && mkdir -p dist/$(PKG)
	cp touchd com.morgan.touchd.plist install.sh uninstall.sh README.md LICENSE dist/$(PKG)/
	tar -C dist -czf dist/$(PKG).tar.gz $(PKG)
	cd dist && shasum -a 256 $(PKG).tar.gz > $(PKG).tar.gz.sha256
	@echo "-> dist/$(PKG).tar.gz"

clean:
	rm -rf touchd touchd-arm64 touchd-x86_64 dist

.PHONY: touchd-universal package clean
