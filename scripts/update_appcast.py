#!/usr/bin/env python3
"""Splice one release into a Sparkle 2 appcast.xml.

Why a script instead of hand-editing: the <enclosure> element must carry the
*exact* byte length of the shipped DMG and the EdDSA signature produced by
Sparkle's ``sign_update``. Get either wrong and every client silently refuses
the update (Sparkle logs the mismatch and moves on). The length is also easy to
get wrong after a re-export, because the DMG is rebuilt byte-for-byte differently
every time.

Design notes
------------
This script deliberately does **text splicing** rather than an ElementTree
round-trip. ElementTree drops the explanatory comment at the top of the feed and
rewrites the CDATA release notes into escaped entities, which turns every single
release into a whole-file diff. Splicing keeps untouched bytes untouched.

Usage
-----
    python3 scripts/update_appcast.py \
        --appcast updater/appcast.xml \
        --version 1.2 \
        --build 2 \
        --dmg Release/DynamicNotch-1.2.dmg \
        --url https://notch.wejoinnwk.com/downloads/DynamicNotch-1.2.dmg \
        --signature-file Release/sparkle-signature.txt \
        --release-notes Release/notes.html

``--signature-file`` may be replaced by ``--signature`` with the raw output of
``sign_update`` (the ``sparkle:edSignature="..." length="..."`` line). The script
parses both values out of it, and cross-checks the length against the actual
DMG on disk when ``--dmg`` is given.

Exit codes: 0 = feed updated, 1 = refused (bad input / placeholder detected).
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

# Locale-independent RFC 822 pieces. strftime's %a/%b follow the process locale,
# and a feed with "周三" in pubDate is technically still parseable but a needless
# way to confuse a future reader.
_WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
_MONTHS = (
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
)

# Items are never nested, so a non-greedy match is unambiguous.
_ITEM_RE = re.compile(r"<item>.*?</item>", re.DOTALL)
_CHANNEL_OPEN = "<channel>"
_CHANNEL_CLOSE = "</channel>"
_VERSION_RE = re.compile(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>")
_ED_SIG_RE = re.compile(r"""edSignature\s*=\s*["']([^"']+)["']""")
_LENGTH_RE = re.compile(r"""length\s*=\s*["'](\d+)["']""")

_PLACEHOLDER_MARKERS = ("TODO", "REPLACE", "PLACEHOLDER", "CHANGEME", "XXX")


def rfc822(when: time.struct_time | None = None) -> str:
    """Return an RFC 822 / RFC 1123 timestamp in UTC, e.g. 'Wed, 23 Sep 2026 02:36:04 +0000'."""
    t = when or time.gmtime()
    return (
        f"{_WEEKDAYS[t.tm_wday]}, {t.tm_mday:02d} {_MONTHS[t.tm_mon - 1]} "
        f"{t.tm_year:04d} {t.tm_hour:02d}:{t.tm_min:02d}:{t.tm_sec:02d} +0000"
    )


def die(message: str) -> "NoReturn":  # noqa: F821 - typing only
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_signature(raw: str, label: str) -> tuple[str, int | None]:
    """Pull (signature, length) out of sign_update output or a bare signature.

    ``sign_update`` prints exactly:
        sparkle:edSignature="<base64>" length="<bytes>"
    so accept that whole line, or just the base64 blob.
    """
    raw = raw.strip()
    if not raw:
        die(f"{label} is empty")

    for marker in _PLACEHOLDER_MARKERS:
        if marker in raw.upper():
            die(
                f"{label} still contains the placeholder '{marker}'. "
                "Refusing to write a feed that no client can verify."
            )

    signature = None
    m = _ED_SIG_RE.search(raw)
    if m:
        signature = m.group(1)
    elif "=" in raw or re.fullmatch(r"[A-Za-z0-9+/=]+", raw):
        # Bare base64 signature (e.g. pasted from a keychain prompt).
        signature = raw.split()[0]
    if not signature:
        die(f"could not find an edSignature value in {label}")

    length = None
    m = _LENGTH_RE.search(raw)
    if m:
        length = int(m.group(1))
    return signature, length


def sparkle_version_of(item_xml: str) -> str | None:
    m = _VERSION_RE.search(item_xml)
    return m.group(1) if m else None


def build_item(
    *,
    title: str,
    pub_date: str,
    link: str,
    build: str,
    version: str,
    min_system_version: str,
    notes_html: str,
    url: str,
    length: int,
    signature: str,
) -> str:
    """Render one <item>, matching the 8/12/16-space indentation of the feed."""
    # A literal ']]>' inside CDATA would terminate the section early.
    safe_notes = notes_html.replace("]]>", "]]&gt;").rstrip("\n")
    return (
        "        <item>\n"
        f"            <title>{escape(title)}</title>\n"
        f"            <pubDate>{escape(pub_date)}</pubDate>\n"
        f"            <link>{escape(link)}</link>\n"
        f"            <sparkle:version>{escape(build)}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>\n"
        f"            <sparkle:minimumSystemVersion>{escape(min_system_version)}</sparkle:minimumSystemVersion>\n"
        "            <description><![CDATA[\n"
        f"{safe_notes}\n"
        "]]></description>\n"
        "            <enclosure\n"
        f"                url={quoteattr(url)}\n"
        f"                sparkle:version={quoteattr(build)}\n"
        f"                sparkle:shortVersionString={quoteattr(version)}\n"
        f'                length="{length}"\n'
        '                type="application/octet-stream"\n'
        f"                sparkle:edSignature={quoteattr(signature)} />\n"
        "        </item>\n"
    )


def splice(text: str, new_item: str, build: str) -> tuple[str, str]:
    """Insert ``new_item`` at the top of the channel, replacing any item with the
    same sparkle:version. Returns (new_text, action)."""
    ch_open = text.find(_CHANNEL_OPEN)
    ch_close = text.find(_CHANNEL_CLOSE)
    if ch_open == -1 or ch_close == -1 or ch_close < ch_open:
        die("appcast has no <channel>...</channel> section")

    inner_start = ch_open + len(_CHANNEL_OPEN)
    region = text[inner_start:ch_close]

    matches = list(_ITEM_RE.finditer(region))
    if not matches:
        # Nothing to anchor on: append just before the closing tag, preserving
        # the trailing indentation that sits in front of </channel>.
        stripped = region.rstrip()
        tail = region[len(stripped):]
        new_region = stripped + "\n" + new_item + tail
        return text[:inner_start] + new_region + text[ch_close:], "inserted (first item)"

    # Layout: gaps[0] item[0] gaps[1] item[1] ... gaps[n-1] item[n-1] trailing
    gaps: list[str] = []
    items: list[str] = []
    pos = 0
    for m in matches:
        gaps.append(region[pos:m.start()])
        items.append(m.group(0))
        pos = m.end()
    trailing = region[pos:]

    kept = [i for i, it in enumerate(items) if sparkle_version_of(it) != build]
    replaced = len(items) - len(kept)

    # gaps[0] is everything between <channel> and the first <item>, and it ends
    # with the indentation that was in front of that item ("\n        "). Drop
    # that trailing indent, otherwise the spliced item lands doubly indented.
    head_gap = gaps[0].rstrip(" \t")
    if not head_gap.endswith("\n"):
        head_gap += "\n"

    # Re-emit the surviving items. Their own leading gap was either consumed as
    # head_gap (the first one) or belonged to a dropped item, so give every one
    # of them an explicit separator and keep the original gaps in between.
    tail = []
    for i in kept:
        tail.append("\n        ")
        tail.append(items[i])
        tail.append(gaps[i + 1] if i + 1 < len(gaps) else trailing)
    if not kept:
        # Every original item was the same build; keep the indent that sits in
        # front of </channel>.
        tail.append(trailing)

    new_region = head_gap + new_item + "".join(tail)

    if replaced:
        action = f"replaced existing build {build}"
    else:
        action = "inserted"
    return text[:inner_start] + new_region + text[ch_close:], action


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--appcast", required=True, help="path to appcast.xml to update in place")
    p.add_argument("--version", required=True, help="marketing version, e.g. 1.2")
    p.add_argument("--build", required=True, help="CFBundleVersion, e.g. 2")
    p.add_argument("--url", required=True, help="download URL of the DMG")
    p.add_argument("--dmg", help="local DMG, used to compute/verify <enclosure length>")
    p.add_argument("--signature", help="raw sign_update output or bare signature")
    p.add_argument("--signature-file", help="file holding sign_update output")
    p.add_argument("--release-notes", help="HTML/markdown file for the release notes")
    p.add_argument("--title", help="item <title> (default: the version)")
    p.add_argument("--link", help="item <link> (default: the URL's origin + /releases)")
    p.add_argument("--min-system-version", default="14.0")
    p.add_argument("--date", help="RFC 822 pubDate override (for reproducible tests)")
    p.add_argument("--dry-run", action="store_true", help="print the result, do not write")
    args = p.parse_args(argv)

    if not re.fullmatch(r"\d+(\.\d+)*", args.version):
        die(f"--version must be dotted digits, got {args.version!r}")
    if not re.fullmatch(r"\d+", args.build) or int(args.build) < 1:
        die(f"--build must be a positive integer, got {args.build!r}")
    if not args.url.startswith("https://"):
        die("--url must be https:// (Sparkle refuses plaintext feeds/downloads)")

    # --- signature + length -------------------------------------------------
    if args.signature and args.signature_file:
        die("pass either --signature or --signature-file, not both")
    if args.signature_file:
        if not os.path.isfile(args.signature_file):
            die(f"--signature-file not found: {args.signature_file}")
        with open(args.signature_file, encoding="utf-8") as fh:
            raw_sig = fh.read()
        label = args.signature_file
    elif args.signature:
        raw_sig, label = args.signature, "--signature"
    else:
        die("need --signature or --signature-file (run Sparkle's sign_update on the DMG)")

    signature, sig_length = parse_signature(raw_sig, label)

    actual_length = None
    if args.dmg:
        if not os.path.isfile(args.dmg):
            die(f"--dmg not found: {args.dmg}")
        actual_length = os.path.getsize(args.dmg)
        if actual_length == 0:
            die(f"--dmg is empty: {args.dmg}")
        if sig_length is not None and sig_length != actual_length:
            die(
                f"length mismatch: sign_update says {sig_length} bytes but "
                f"{args.dmg} is {actual_length} bytes. The DMG was rebuilt after "
                "it was signed - re-run sign_update on the exact file you ship."
            )
    length = sig_length if sig_length is not None else actual_length
    if length is None:
        die("cannot determine <enclosure length>: pass --dmg, or sign_update output that includes length=")

    # --- release notes ------------------------------------------------------
    if args.release_notes:
        if not os.path.isfile(args.release_notes):
            die(f"--release-notes not found: {args.release_notes}")
        with open(args.release_notes, encoding="utf-8") as fh:
            notes = fh.read().strip()
    else:
        notes = f"<h2>DynamicNotch {escape(args.version)}</h2>"
    if not notes:
        die("release notes are empty")

    # --- appcast ------------------------------------------------------------
    if not os.path.isfile(args.appcast):
        die(f"--appcast not found: {args.appcast}")
    with open(args.appcast, encoding="utf-8") as fh:
        text = fh.read()

    # Default the item <link> to the feed's own <link> rather than inventing a
    # URL; CI passes an explicit --link pointing at the GitHub release page.
    link = args.link
    if not link:
        m = re.search(r"<link>\s*([^<]+?)\s*</link>", text)
        link = m.group(1) if m else args.url
    item = build_item(
        title=args.title or args.version,
        pub_date=args.date or rfc822(),
        link=link,
        build=args.build,
        version=args.version,
        min_system_version=args.min_system_version,
        notes_html=notes,
        url=args.url,
        length=length,
        signature=signature,
    )
    updated, action = splice(text, item, args.build)

    # Hard gate: the feed we are about to write must actually parse. This
    # catches the classic footgun that bit this file once already - a double
    # hyphen inside an XML comment (e.g. a pasted "--flag" in the header) makes
    # the whole document invalid, and Sparkle would then see no updates at all.
    try:
        ET.fromstring(updated)
    except ET.ParseError as exc:
        die(f"the updated feed is not well-formed XML ({exc}); refusing to write it")

    if args.dry_run:
        print(updated)
        print(f"\n[dry-run] would have {action} for build {args.build}", file=sys.stderr)
        return 0

    with open(args.appcast, "w", encoding="utf-8") as fh:
        fh.write(updated)
    print(f"{args.appcast}: {action} -> {args.version} (build {args.build}), {length} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
