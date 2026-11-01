#!/usr/bin/env python3
"""Bump DynamicNotch project version and build number.

Reads CURRENT_PROJECT_VERSION and MARKETING_VERSION from project.pbxproj,
compares with the highest published build in website/appcast.xml,
computes the next build number (auto-increment if omitted),
and safely updates project.pbxproj and website/download.html.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import NoReturn

CURRENT_VERSION_PATTERN = re.compile(r"(CURRENT_PROJECT_VERSION\s*=\s*)([^;]+)(;)")
MARKETING_VERSION_PATTERN = re.compile(r"(MARKETING_VERSION\s*=\s*)([^;]+)(;)")
APPCAST_VERSION_PATTERN = re.compile(r"<sparkle:version>\s*([0-9]+)\s*</sparkle:version>")
DOWNLOAD_PILL_PATTERN = re.compile(r"(<div class=\"download-version-pill\">[\s\S]*?<span>)v[0-9]+(\.[0-9]+)*(</span>)")
DOWNLOAD_DMG_PATTERN = re.compile(r"(href=\"[^\"]*DynamicNotch-)[0-9]+(\.[0-9]+)*(\.dmg\")")


def logError(errorMessage: str) -> NoReturn:
    # Print error message and exit with code 1.
    print(f"error: {errorMessage}", file=sys.stderr)
    raise SystemExit(1)


def readPbxprojVersions(pbxprojContent: str) -> tuple[str, int]:
    # Read marketing version and current project build version from project.pbxproj content.
    marketingMatches = MARKETING_VERSION_PATTERN.findall(pbxprojContent)
    currentMatches = CURRENT_VERSION_PATTERN.findall(pbxprojContent)

    if not marketingMatches:
        logError("could not find MARKETING_VERSION in project.pbxproj")
    if not currentMatches:
        logError("could not find CURRENT_PROJECT_VERSION in project.pbxproj")

    rawMarketing = marketingMatches[0][1].strip().strip('"\'')
    rawCurrent = currentMatches[0][1].strip().strip('"\'')

    try:
        currentBuild = int(rawCurrent)
    except ValueError:
        logError(f"CURRENT_PROJECT_VERSION is not an integer: '{rawCurrent}'")

    return rawMarketing, currentBuild


def readAppcastHighestBuild(appcastContent: str) -> int:
    # Extract the highest build integer from appcast xml content.
    matches = APPCAST_VERSION_PATTERN.findall(appcastContent)
    if not matches:
        return 0
    return max(int(versionText) for versionText in matches)


def computeNextVersionAndBuild(
    pbxprojVersion: str,
    pbxprojBuild: int,
    appcastHighestBuild: int,
    inputVersion: str | None = None,
    inputBuild: str | None = None,
) -> tuple[str, int]:
    # Calculate target marketing version and target build number.
    cleanVersion = inputVersion.strip() if inputVersion else ""
    cleanBuild = inputBuild.strip() if inputBuild else ""

    if cleanVersion:
        if not re.fullmatch(r"[0-9]+(\.[0-9]+)*", cleanVersion):
            logError(f"version must be dotted digits, got '{cleanVersion}'")
        targetVersion = cleanVersion
    else:
        targetVersion = pbxprojVersion

    if cleanBuild:
        if not re.fullmatch(r"[0-9]+", cleanBuild) or int(cleanBuild) < 1:
            logError(f"build must be a positive integer, got '{cleanBuild}'")
        targetBuild = int(cleanBuild)
        if targetBuild <= appcastHighestBuild:
            logError(
                f"build {targetBuild} is not greater than {appcastHighestBuild}, "
                "the highest build already in the feed"
            )
    else:
        baseBuild = max(pbxprojBuild, appcastHighestBuild)
        targetBuild = baseBuild + 1

    return targetVersion, targetBuild


def updatePbxprojContent(content: str, newVersion: str, newBuild: int) -> str:
    # Replace CURRENT_PROJECT_VERSION and MARKETING_VERSION across all configurations.
    updatedContent = CURRENT_VERSION_PATTERN.sub(rf"\g<1>{newBuild}\g<3>", content)
    updatedContent = MARKETING_VERSION_PATTERN.sub(rf"\g<1>{newVersion}\g<3>", updatedContent)
    return updatedContent


def updateDownloadHtmlContent(content: str, newVersion: str) -> str:
    # Update version text and DMG download link in download.html.
    updatedContent = DOWNLOAD_PILL_PATTERN.sub(rf"\g<1>v{newVersion}\g<3>", content)
    updatedContent = DOWNLOAD_DMG_PATTERN.sub(rf"\g<1>{newVersion}\g<3>", updatedContent)
    return updatedContent


def main(argv: list[str] | None = None) -> int:
    # CLI entry point for bump_version.
    argParser = argparse.ArgumentParser(description="Bump DynamicNotch project versions")
    argParser.add_argument("--pbxproj", default="DynamicNotch.xcodeproj/project.pbxproj", help="Path to project.pbxproj")
    argParser.add_argument("--appcast", default="website/appcast.xml", help="Path to website/appcast.xml")
    argParser.add_argument("--download-html", default="website/download.html", help="Path to website/download.html")
    argParser.add_argument("--version", default="", help="New marketing version (empty = keep current)")
    argParser.add_argument("--build", default="", help="New build number (empty = auto-increment)")
    argParser.add_argument("--write", action="store_true", help="Write changes to disk")
    argParser.add_argument("--github-output", default="", help="Path to GITHUB_OUTPUT file")
    args = argParser.parse_args(argv)

    if not os.path.exists(args.pbxproj):
        logError(f"project.pbxproj not found at {args.pbxproj}")

    with open(args.pbxproj, "r", encoding="utf-8") as fileHandler:
        pbxprojContent = fileHandler.read()

    appcastContent = ""
    if os.path.exists(args.appcast):
        with open(args.appcast, "r", encoding="utf-8") as fileHandler:
            appcastContent = fileHandler.read()

    currentVersion, currentBuild = readPbxprojVersions(pbxprojContent)
    highestAppcastBuild = readAppcastHighestBuild(appcastContent)

    targetVersion, targetBuild = computeNextVersionAndBuild(
        currentVersion,
        currentBuild,
        highestAppcastBuild,
        args.version,
        args.build,
    )

    print(f"Marketing version: {currentVersion} -> {targetVersion}")
    print(f"Build version:     {currentBuild} (appcast highest: {highestAppcastBuild}) -> {targetBuild}")

    if args.write:
        newPbxprojContent = updatePbxprojContent(pbxprojContent, targetVersion, targetBuild)
        with open(args.pbxproj, "w", encoding="utf-8") as fileHandler:
            fileHandler.write(newPbxprojContent)
        print(f"Updated {args.pbxproj}")

        if os.path.exists(args.download_html):
            with open(args.download_html, "r", encoding="utf-8") as fileHandler:
                downloadContent = fileHandler.read()
            newDownloadContent = updateDownloadHtmlContent(downloadContent, targetVersion)
            with open(args.download_html, "w", encoding="utf-8") as fileHandler:
                fileHandler.write(newDownloadContent)
            print(f"Updated {args.download_html}")

    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as fileHandler:
            fileHandler.write(f"version={targetVersion}\n")
            fileHandler.write(f"build={targetBuild}\n")
        print(f"Written outputs to {args.github_output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
