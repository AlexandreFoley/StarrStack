#!/usr/bin/env python3
"""Refresh the checked-in Radarr and Sonarr OpenAPI reference documents."""

import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parent.parent
DOCUMENTS = {
    "radarr.json": "https://raw.githubusercontent.com/Radarr/Radarr/develop/src/Radarr.Api.V3/openapi.json",
    "sonarrv3.json": "https://raw.githubusercontent.com/Sonarr/Sonarr/develop/src/Sonarr.Api.V3/openapi.json",
}


def update(name: str, source_url: str, downloaded_at: str) -> None:
    with urlopen(source_url, timeout=30) as response:
        document = json.load(response)

    if not isinstance(document, dict) or not document.get("openapi"):
        raise ValueError(f"{source_url} did not return an OpenAPI document")

    document["x-source-url"] = source_url
    document["x-downloaded-at"] = downloaded_at

    destination = ROOT / "arrAPI" / name
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=destination.parent, delete=False
    ) as temporary:
        json.dump(document, temporary, indent=2)
        temporary.write("\n")
        temporary_name = temporary.name
    os.replace(temporary_name, destination)


def main() -> None:
    downloaded_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    for name, source_url in DOCUMENTS.items():
        update(name, source_url, downloaded_at)
        print(f"updated {name} ({downloaded_at})")


if __name__ == "__main__":
    main()
