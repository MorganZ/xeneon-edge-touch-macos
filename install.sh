#!/bin/sh
set -e
cd "$(dirname "$0")"
swiftc -O -o touchd touchd.swift
sudo install -m 755 touchd /usr/local/bin/touchd
launchctl unload ~/Library/LaunchAgents/com.morgan.touchd.plist 2>/dev/null || true
cp com.morgan.touchd.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.morgan.touchd.plist
echo "Installed. Grant /usr/local/bin/touchd in System Settings > Privacy & Security >"
echo "  Input Monitoring  and  Accessibility, then: launchctl kickstart -k gui/$(id -u)/com.morgan.touchd"
