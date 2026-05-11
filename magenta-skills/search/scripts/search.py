# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "httpx>=0.27",
# ]
# ///
"""Brave Search API CLI.

Reads BRAVE_SEARCH_API_KEY from the environment, queries the Brave Search
web endpoint, and prints results as JSON.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import httpx

BRAVE_ENDPOINT = "https://api.search.brave.com/res/v1/web/search"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Search the web via the Brave Search API.")
    parser.add_argument("query", nargs="+", help="Search query (joined with spaces).")
    parser.add_argument("--count", type=int, default=10, help="Number of results (max 20).")
    parser.add_argument("--offset", type=int, default=0, help="Pagination offset.")
    parser.add_argument("--country", default="US", help="Country code, e.g. US, GB.")
    parser.add_argument(
        "--freshness",
        default=None,
        help="Freshness filter: pd, pw, pm, py, or YYYY-MM-DDtoYYYY-MM-DD.",
    )
    parser.add_argument("--raw", action="store_true", help="Print raw API response JSON.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    api_key = os.environ.get("BRAVE_SEARCH_API_KEY")
    if not api_key:
        print("error: BRAVE_SEARCH_API_KEY is not set", file=sys.stderr)
        return 2

    params: dict[str, str | int] = {
        "q": " ".join(args.query),
        "count": max(1, min(args.count, 20)),
        "offset": max(0, args.offset),
        "country": args.country,
    }
    if args.freshness:
        params["freshness"] = args.freshness

    headers = {
        "Accept": "application/json",
        "Accept-Encoding": "gzip",
        "X-Subscription-Token": api_key,
    }

    try:
        response = httpx.get(BRAVE_ENDPOINT, params=params, headers=headers, timeout=30.0)
    except httpx.HTTPError as exc:
        print(f"error: request failed: {exc}", file=sys.stderr)
        return 1

    if response.status_code != 200:
        print(
            f"error: Brave API returned {response.status_code}: {response.text}",
            file=sys.stderr,
        )
        return 1

    data = response.json()

    if args.raw:
        json.dump(data, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    web_results = data.get("web", {}).get("results", []) or []
    condensed = [
        {
            "title": r.get("title", ""),
            "url": r.get("url", ""),
            "description": r.get("description", ""),
        }
        for r in web_results
    ]
    json.dump(condensed, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
