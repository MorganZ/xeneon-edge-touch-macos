#!/bin/sh
launchctl unload ~/Library/LaunchAgents/com.morgan.touchd.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.morgan.touchd.plist
sudo rm -f /usr/local/bin/touchd
echo "Removed. You may also remove touchd from Input Monitoring / Accessibility."
