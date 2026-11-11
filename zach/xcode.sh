# Sourced by build.sh and update.sh. Upstream builds with the newest Xcode, so the fork uses the
# newest one installed in /Applications through DEVELOPER_DIR. The system default
# (xcode-select) is left alone for other projects. An explicit DEVELOPER_DIR wins.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    newest_xcode=$(
        for app in /Applications/Xcode*.app; do
            v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null) || continue
            echo "$v $app"
        done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -d' ' -f2-
    )
    [ -n "$newest_xcode" ] || { echo "xcode.sh: no Xcode found in /Applications" >&2; exit 1; }
    export DEVELOPER_DIR="$newest_xcode/Contents/Developer"
fi
echo "using $(xcodebuild -version | head -1) at $DEVELOPER_DIR"
