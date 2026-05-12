#!/usr/bin/env ruby
# Injects SystemCapabilities into the app target's TargetAttributes after XcodeGen
# generation. XcodeGen 2.x silently ignores the `capabilities` key in project.yml,
# so this script is the only reliable way to keep CloudKit, Push, and WeatherKit
# visible in Xcode's Signing & Capabilities tab.

PBXPROJ = "HeroDirt.xcodeproj/project.pbxproj"
APP_TARGET = "HeroDirt"
TEAM = "K3CQQKBR25"

content = File.read(PBXPROJ)

# Locate the UUID for the app target by finding its PBXNativeTarget comment.
# Format in pbxproj: "UUID /* HeroDirt */ = {\n\t\t\tisa = PBXNativeTarget;"
app_uuid = content[/(\w{24}) \/\* #{Regexp.escape(APP_TARGET)} \*\/ = \{\s+isa = PBXNativeTarget;/, 1]
abort "ERROR: Could not find #{APP_TARGET} target UUID in #{PBXPROJ}" unless app_uuid

system_capabilities = <<~CAPS
\t\t\t\t\t\tSystemCapabilities = {
\t\t\t\t\t\t\t"com.apple.iCloud" = {
\t\t\t\t\t\t\t\tenabled = 1;
\t\t\t\t\t\t\t};
\t\t\t\t\t\t\t"com.apple.Push" = {
\t\t\t\t\t\t\t\tenabled = 1;
\t\t\t\t\t\t\t};
\t\t\t\t\t\t\t"com.apple.WeatherKit" = {
\t\t\t\t\t\t\t\tenabled = 1;
\t\t\t\t\t\t\t};
\t\t\t\t\t\t};
CAPS

# Find the app target's dict inside TargetAttributes and inject SystemCapabilities.
# The XcodeGen-generated entry looks like:
#   UUID = {
#       DevelopmentTeam = TEAMID;
#   };
pattern = /(#{Regexp.escape(app_uuid)} = \{\n\t+DevelopmentTeam = #{Regexp.escape(TEAM)};\n)(\t+\};)/

unless content.match?(pattern)
  abort "ERROR: Expected TargetAttributes pattern not found for #{app_uuid}. " \
        "Was the project regenerated with a different team ID or XcodeGen version?"
end

patched = content.sub(pattern, "\\1#{system_capabilities}\\2")
File.write(PBXPROJ, patched)
puts "✓ SystemCapabilities injected for target #{APP_TARGET} (#{app_uuid})"
