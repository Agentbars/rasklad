#!/bin/zsh
# Writes a one-item Sparkle appcast for a release zip to stdout.
#   scripts/make-appcast.sh <version> <zip> <ed-private-key-file> [download-url]
# The release workflow attaches the result to the GitHub release as appcast.xml, so
# SUFeedURL (.../releases/latest/download/appcast.xml) always describes the newest release.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$1 ZIP=$2 KEY=$3
TAG=v$VERSION
URL=${4:-https://github.com/Agentbars/rasklad/releases/download/$TAG/Rasklad-$TAG.zip}
SIGN_UPDATE=$(ls build/deps/Sparkle-*/bin/sign_update | head -1)

# Prints: sparkle:edSignature="..." length="..."
ATTRS=$("$SIGN_UPDATE" --ed-key-file "$KEY" "$ZIP")
[[ "$ATTRS" == *edSignature=* && "$ATTRS" == *length=* ]] || { echo "sign_update failed: $ATTRS" >&2; exit 1; }
MIN_OS=$(plutil -extract LSMinimumSystemVersion raw Info.plist)
DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Rasklad</title>
    <link>https://github.com/Agentbars/rasklad</link>
    <item>
      <title>Rasklad $VERSION</title>
      <link>https://github.com/Agentbars/rasklad/releases/tag/$TAG</link>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>Что нового: <a href="https://github.com/Agentbars/rasklad/releases/tag/$TAG">Rasklad $TAG на GitHub</a>.</p>]]></description>
      <pubDate>$DATE</pubDate>
      <enclosure url="$URL" type="application/octet-stream" $ATTRS />
    </item>
  </channel>
</rss>
XML
