# Arr API reference documents

This directory contains checked-in OpenAPI snapshots used as reference when
writing API calls in the configuration scripts. They are documentation for
contributors; they are not copied into the container image and are not runtime
inputs.

## Updating the snapshots

From the repository root, run:

```bash
python3 scripts/update-api-docs.py
```

The script downloads the current OpenAPI documents from the Radarr and Sonarr
repositories, validates that each response is an OpenAPI document, and writes
them atomically. Each file records:

- `x-source-url`: the upstream URL used for the download
- `x-downloaded-at`: the UTC time when the download started

These `x-` fields are OpenAPI specification extensions, so OpenAPI tooling can
ignore them safely. Review the generated diff before committing because an
upstream update may change available endpoints or request fields.
