#!/usr/bin/env python3
"""Generate the HTML release-notes body that goes into the appcast <description>.

Kept as a script rather than an inline heredoc in the workflow so it can be run
and eyeballed locally:

    scripts/generate_release_notes.py 1.2 --range v1.1..HEAD

Notes are plain HTML because Sparkle renders <description> in a WebView. The
output is intentionally boring - a heading plus one <li> per non-merge commit
subject - so a release never depends on someone remembering to write notes.

Everything is HTML-escaped: commit subjects routinely contain `<`, `>` and `&`,
and an unescaped one would produce an appcast that fails to parse (which Sparkle
treats as "no updates available", silently).
"""

from __future__ import annotations

import argparse
import html
import subprocess
import sys


def commit_subjects(rng: str) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "log", "--no-merges", "--pretty=format:%s", rng],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except FileNotFoundError:
        print("error: git is not available", file=sys.stderr)
        raise SystemExit(1)
    except subprocess.CalledProcessError as exc:
        print(f"error: git log failed for range '{rng}': {exc.stderr.strip()}", file=sys.stderr)
        raise SystemExit(1)

    subjects = [line.strip() for line in out.splitlines() if line.strip()]
    return subjects


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("version", help="marketing version, used for the heading")
    p.add_argument("--range", default="HEAD", help="git revision range, e.g. v1.1..HEAD (default: HEAD)")
    p.add_argument("--limit", type=int, default=30, help="maximum number of bullets (default: 30)")
    p.add_argument("--intro", help="extra sentence placed under the heading")
    args = p.parse_args(argv)

    subjects = commit_subjects(args.range)[: args.limit]
    if not subjects:
        subjects = ["Maintenance release"]

    lines = [f"<h2>DynamicNotch {html.escape(args.version)}</h2>"]
    if args.intro:
        lines.append(f"<p>{html.escape(args.intro)}</p>")
    lines.append("<ul>")
    for s in subjects:
        lines.append(f"    <li>{html.escape(s)}</li>")
    lines.append("</ul>")

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
