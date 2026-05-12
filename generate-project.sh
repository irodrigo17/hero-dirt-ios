#!/bin/bash
# Regenerate HeroDirt.xcodeproj and apply post-generation patches.
# Always use this script instead of running xcodegen directly.
set -euo pipefail

/opt/homebrew/bin/xcodegen generate
ruby scripts/add-capabilities.rb
