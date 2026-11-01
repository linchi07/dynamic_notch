#!/usr/bin/env python3
"""Unit tests for scripts/bump_version.py."""

from __future__ import annotations

import os
import tempfile
import unittest

from scripts.bump_version import (
    computeNextVersionAndBuild,
    readAppcastHighestBuild,
    readPbxprojVersions,
    updateDownloadHtmlContent,
    updatePbxprojContent,
)

SAMPLE_PBXPROJ = """// !$*UTF8*$!
{
	objects = {
		9110B6B02BF5904D00701053 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CURRENT_PROJECT_VERSION = 3;
				MARKETING_VERSION = 10.1;
			};
			name = Debug;
		};
		9110B6B12BF5904D00701053 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CURRENT_PROJECT_VERSION = 3;
				MARKETING_VERSION = 10.1;
			};
			name = Release;
		};
	};
}
"""

SAMPLE_APPCAST = """<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <item>
            <title>10.1</title>
            <sparkle:version>3</sparkle:version>
            <sparkle:shortVersionString>10.1</sparkle:shortVersionString>
        </item>
        <item>
            <title>10.0</title>
            <sparkle:version>2</sparkle:version>
            <sparkle:shortVersionString>10.0</sparkle:shortVersionString>
        </item>
    </channel>
</rss>
"""

SAMPLE_DOWNLOAD_HTML = """
<div class="download-version-pill">
  <span class="download-version-dot"></span>
  <span>v10.0</span>
  <span>·</span>
  <span>Universal (Apple Silicon & Intel)</span>
</div>
<a id="directDownloadBtn" href="https://download.wejoinnwk.com/DynamicNotch-10.0.dmg" class="btn-download-primary">
"""


class BumpVersionTests(unittest.TestCase):
    def testReadPbxprojVersions(self) -> None:
        marketingVersion, currentBuild = readPbxprojVersions(SAMPLE_PBXPROJ)
        self.assertEqual(marketingVersion, "10.1")
        self.assertEqual(currentBuild, 3)

    def testReadAppcastHighestBuild(self) -> None:
        highestBuild = readAppcastHighestBuild(SAMPLE_APPCAST)
        self.assertEqual(highestBuild, 3)

        emptyFeedBuild = readAppcastHighestBuild("<rss><channel></channel></rss>")
        self.assertEqual(emptyFeedBuild, 0)

    def testAutoIncrementBuild(self) -> None:
        targetVersion, targetBuild = computeNextVersionAndBuild(
            pbxprojVersion="10.1",
            pbxprojBuild=3,
            appcastHighestBuild=3,
            inputVersion=None,
            inputBuild=None,
        )
        self.assertEqual(targetVersion, "10.1")
        self.assertEqual(targetBuild, 4)

    def testCustomVersionWithAutoBuild(self) -> None:
        targetVersion, targetBuild = computeNextVersionAndBuild(
            pbxprojVersion="10.1",
            pbxprojBuild=3,
            appcastHighestBuild=3,
            inputVersion="10.2",
            inputBuild=None,
        )
        self.assertEqual(targetVersion, "10.2")
        self.assertEqual(targetBuild, 4)

    def testCustomBuildValid(self) -> None:
        targetVersion, targetBuild = computeNextVersionAndBuild(
            pbxprojVersion="10.1",
            pbxprojBuild=3,
            appcastHighestBuild=3,
            inputVersion=None,
            inputBuild="10",
        )
        self.assertEqual(targetVersion, "10.1")
        self.assertEqual(targetBuild, 10)

    def testCustomBuildLesserThanAppcastFails(self) -> None:
        with self.assertRaises(SystemExit):
            computeNextVersionAndBuild(
                pbxprojVersion="10.1",
                pbxprojBuild=3,
                appcastHighestBuild=3,
                inputVersion=None,
                inputBuild="2",
            )

    def testInvalidVersionFormatFails(self) -> None:
        with self.assertRaises(SystemExit):
            computeNextVersionAndBuild(
                pbxprojVersion="10.1",
                pbxprojBuild=3,
                appcastHighestBuild=3,
                inputVersion="v10.2-alpha",
                inputBuild=None,
            )

    def testUpdatePbxprojContent(self) -> None:
        updated = updatePbxprojContent(SAMPLE_PBXPROJ, "10.2", 4)
        marketingVersion, currentBuild = readPbxprojVersions(updated)
        self.assertEqual(marketingVersion, "10.2")
        self.assertEqual(currentBuild, 4)

    def testUpdateDownloadHtmlContent(self) -> None:
        updated = updateDownloadHtmlContent(SAMPLE_DOWNLOAD_HTML, "10.2")
        self.assertIn("<span>v10.2</span>", updated)
        self.assertIn("href=\"https://download.wejoinnwk.com/DynamicNotch-10.2.dmg\"", updated)

    def testCliDryRunAndWrite(self) -> None:
        with tempfile.TemporaryDirectory() as tempDir:
            tempPbxproj = os.path.join(tempDir, "project.pbxproj")
            tempAppcast = os.path.join(tempDir, "appcast.xml")
            tempDownload = os.path.join(tempDir, "download.html")
            tempOutput = os.path.join(tempDir, "output.txt")

            with open(tempPbxproj, "w", encoding="utf-8") as f:
                f.write(SAMPLE_PBXPROJ)
            with open(tempAppcast, "w", encoding="utf-8") as f:
                f.write(SAMPLE_APPCAST)
            with open(tempDownload, "w", encoding="utf-8") as f:
                f.write(SAMPLE_DOWNLOAD_HTML)

            from scripts.bump_version import main as bumpMain

            # Dry run test
            bumpMain([
                "--pbxproj", tempPbxproj,
                "--appcast", tempAppcast,
                "--download-html", tempDownload,
                "--version", "10.2",
            ])
            with open(tempPbxproj, "r", encoding="utf-8") as f:
                self.assertIn("CURRENT_PROJECT_VERSION = 3;", f.read())

            # Real write test
            bumpMain([
                "--pbxproj", tempPbxproj,
                "--appcast", tempAppcast,
                "--download-html", tempDownload,
                "--version", "10.2",
                "--write",
                "--github-output", tempOutput,
            ])
            with open(tempPbxproj, "r", encoding="utf-8") as f:
                content = f.read()
                self.assertIn("CURRENT_PROJECT_VERSION = 4;", content)
                self.assertIn("MARKETING_VERSION = 10.2;", content)

            with open(tempDownload, "r", encoding="utf-8") as f:
                content = f.read()
                self.assertIn("<span>v10.2</span>", content)
                self.assertIn("DynamicNotch-10.2.dmg", content)

            with open(tempOutput, "r", encoding="utf-8") as f:
                outputContent = f.read()
                self.assertIn("version=10.2\n", outputContent)
                self.assertIn("build=4\n", outputContent)


if __name__ == "__main__":
    unittest.main()
