#!/bin/bash
# Replaces the nix-darwin `system.defaults`.
# Pointer size (1.5) stays manual: com.apple.universalaccess is SIP-protected,
# so only a process with Full Disk Access can write it.
set -euo pipefail

defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
defaults write NSGlobalDomain KeyRepeat -int 3
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
defaults write com.apple.finder CreateDesktop -bool false

defaults write com.apple.dock autohide -bool true
# No autohide-delay: on macOS 26 a 0.0 delay stops hover-to-reveal completely.
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock largesize -int 65
defaults write com.apple.dock tilesize -int 50
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock mineffect -string genie
defaults write com.apple.dock orientation -string bottom

# Apply the NSGlobalDomain changes without a logout, as nix-darwin did.
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
killall Dock Finder
