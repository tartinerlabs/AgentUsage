#!/usr/bin/env python3

import argparse
import html
import os
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--markdown", required=True)
    parser.add_argument("--html", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--title", default="What's New")
    parser.add_argument("--notes-file")
    args = parser.parse_args()

    if args.notes_file:
        notes = Path(args.notes_file).read_text(encoding="utf-8").strip()
    else:
        notes = os.environ.get("NOTES", "").strip()
    lines = [line.strip() for line in notes.splitlines() if line.strip()]
    bullets = [line[2:] if line.startswith("- ") else line for line in lines]
    changelog_url = f"https://github.com/{args.repository}/blob/main/CHANGELOG.md"

    markdown_lines = [f"## {args.title}", ""]
    markdown_lines.extend(f"- {line}" for line in bullets)
    markdown_lines.extend(["", f"See [CHANGELOG.md]({changelog_url}) for full details.", ""])
    Path(args.markdown).write_text("\n".join(markdown_lines), encoding="utf-8")

    html_lines = [f"<h2>{html.escape(args.title)}</h2>"]
    if bullets:
        html_lines.append("<ul>")
        html_lines.extend(f"<li>{html.escape(line)}</li>" for line in bullets)
        html_lines.append("</ul>")
    html_lines.append(
        f'<p>See <a href="{html.escape(changelog_url, quote=True)}">CHANGELOG.md</a> for full details.</p>'
    )
    Path(args.html).write_text("\n".join(html_lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
