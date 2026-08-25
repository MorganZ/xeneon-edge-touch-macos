#!/bin/sh
# Installs touchd as a LaunchAgent. Works from a source checkout (builds with swiftc)
# or from a release package (uses the bundled universal binary).
set -e
cd "$(dirname "$0")"

if [ -f touchd.swift ] && command -v swiftc >/dev/null 2>&1; then
  echo "Building touchd..."
  swiftc -O -o touchd touchd.swift
elif [ ! -x touchd ]; then
  echo "No touchd binary and no swiftc available. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

# Downloaded packages are quarantined by Gatekeeper; the binary is not notarized.
xattr -d com.apple.quarantine touchd 2>/dev/null || true

sudo install -m 755 touchd /usr/local/bin/touchd
launchctl unload ~/Library/LaunchAgents/com.morgan.touchd.plist 2>/dev/null || true
cp com.morgan.touchd.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.morgan.touchd.plist

cat <<EOF

Installed. Now grant /usr/local/bin/touchd two permissions in
System Settings > Privacy & Security (press Cmd-Shift-G in the file picker to type the path):
  - Input Monitoring
  - Accessibility
then restart it:
  launchctl kickstart -k gui/$(id -u)/com.morgan.touchd
EOF
