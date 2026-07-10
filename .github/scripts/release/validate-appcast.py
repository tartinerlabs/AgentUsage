#!/usr/bin/env python3

import argparse
from collections import Counter
import sys
import xml.etree.ElementTree as ET


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def sparkle(name: str) -> str:
    return f"{{{SPARKLE_NAMESPACE}}}{name}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("appcast")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True)
    args = parser.parse_args()

    root = ET.parse(args.appcast).getroot()
    builds = [item.findtext(sparkle("version")) for item in root.findall("./channel/item")]
    duplicates = sorted(build for build, count in Counter(builds).items() if build and count > 1)
    if duplicates:
        raise SystemExit(f"appcast contains duplicate build entries: {', '.join(duplicates)}")

    matches = []
    for item in root.findall("./channel/item"):
        build = item.findtext(sparkle("version"))
        if build == args.build:
            matches.append(item)

    if len(matches) != 1:
        raise SystemExit(f"expected exactly one appcast item for build {args.build}, found {len(matches)}")

    item = matches[0]
    version = item.findtext(sparkle("shortVersionString"))
    if version != args.version:
        raise SystemExit(f"expected version {args.version}, found {version!r}")

    enclosure = item.find("enclosure")
    if enclosure is None:
        raise SystemExit("release item has no enclosure")
    if enclosure.get("url") != args.url:
        raise SystemExit(f"unexpected download URL: {enclosure.get('url')!r}")

    signature = enclosure.get(sparkle("edSignature"), "")
    if not signature:
        raise SystemExit("release enclosure has no Sparkle EdDSA signature")

    print(signature)


if __name__ == "__main__":
    try:
        main()
    except ET.ParseError as error:
        print(f"invalid appcast XML: {error}", file=sys.stderr)
        raise SystemExit(1) from error
