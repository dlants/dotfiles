# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "trafilatura>=2.0",
# ]
# ///
"""Fetch a URL and extract its main text content using trafilatura."""
from __future__ import annotations

import argparse
import sys

import trafilatura


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch a URL and extract main content.")
    parser.add_argument("url", help="URL to fetch.")
    parser.add_argument(
        "--format",
        choices=["txt", "markdown", "html", "json"],
        default="markdown",
        help="Output format (default: markdown).",
    )
    parser.add_argument(
        "--include-links",
        action="store_true",
        help="Preserve hyperlinks in the output.",
    )
    parser.add_argument(
        "--include-images",
        action="store_true",
        help="Preserve image references in the output.",
    )
    parser.add_argument(
        "--include-tables",
        action="store_true",
        default=True,
        help="Preserve tables (default: on).",
    )
    parser.add_argument(
        "--with-metadata",
        action="store_true",
        help="Include metadata (title, author, date) in the output.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    downloaded = trafilatura.fetch_url(args.url)
    if downloaded is None:
        print(f"error: failed to fetch {args.url}", file=sys.stderr)
        return 1

    result = trafilatura.extract(
        downloaded,
        output_format=args.format,
        include_links=args.include_links,
        include_images=args.include_images,
        include_tables=args.include_tables,
        with_metadata=args.with_metadata,
        url=args.url,
    )

    if result is None:
        print("error: could not extract content from page", file=sys.stderr)
        return 1

    sys.stdout.write(result)
    if not result.endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
