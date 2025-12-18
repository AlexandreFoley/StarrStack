# Starr - Unified Arr Services Container

A disk-space optimized Podman/Docker image containing Radarr, Sonarr, Prowlarr, and Unpackerr running under systemd. Image size: **~700MB**.

## Features

- **Single unified container**: All 4 services run together under systemd init
- **Lightweight**: Multi-stage build + file deduplication saves 53% vs original size
- **Smart configuration**: Environment variables auto-sync across services
- **Pre-configured**: Ready to run with sensible defaults
- **Customizable**: Override any setting at runtime

## Services Included

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| **Radarr** | 7878 | http://127.0.0.1:7878 | Movie management |
| **Sonarr** | 8989 | http://127.0.0.1:8989 | TV series management |
| **Prowlarr** | 9696 | http://127.0.0.1:9696 | Indexer management |
| **Unpackerr** | N/A | N/A | Automatic archive extraction |

## Quick Start

### Building the Image

```bash
podman build -t starr -f ubi.dockerfile .
```

### Running the Container

```bash
podman run -d \
  --name starr \
  -p 7878:7878 \
  -p 8989:8989 \
  -p 9696:9696 \
  -v config:/config \
  -v media:/media \
  starr
```

## Configuration & Customization

### Environment Variables

All configuration is controlled via environment variables. Changes to these variables override the defaults baked into the image.

#### Authentication Settings

All services use the same API key by default. Override individually if needed:

| Variable | Default | Description |
|----------|---------|-------------|
| `RADARR__AUTH__APIKEY` | `c59b53...` | Radarr API key (32-char hex) |
| `SONARR__AUTH__APIKEY` | `c59b53...` | Sonarr API key (32-char hex) |
| `PROWLARR__AUTH__APIKEY` | `c59b53...` | Prowlarr API key (32-char hex) |
| `RADARR__AUTH__ENABLED` | `false` | Enable auth in Radarr |
| `SONARR__AUTH__ENABLED` | `false` | Enable auth in Sonarr |
| `PROWLARR__AUTH__ENABLED` | `false` | Enable auth in Prowlarr |
| `RADARR__AUTH__METHOD` | `External` | Auth method (External, Forms, ApiKey) |
| `SONARR__AUTH__METHOD` | `External` | Auth method (External, Forms, ApiKey) |
| `PROWLARR__AUTH__METHOD` | `External` | Auth method (External, Forms, ApiKey) |

#### Server Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `RADARR__SERVER__PORT` | `7878` | Radarr listen port |
| `SONARR__SERVER__PORT` | `8989` | Sonarr listen port |
| `RADARR__SERVER__URLBASE` | `` | Radarr URL base path (e.g., `/radarr`) |
| `SONARR__SERVER__URLBASE` | `` | Sonarr URL base path (e.g., `/sonarr`) |
| `PROWLARR__SERVER__URLBASE` | `` | Prowlarr URL base path (e.g., `/prowlarr`) |

#### Unpackerr Settings

Unpackerr automatically syncs with Radarr and Sonarr:

| Variable | Default | Description |
|----------|---------|-------------|
| `UN_RADARR_0_API_KEY` | Auto-synced | Unpackerr's Radarr API key (auto-uses RADARR__AUTH__APIKEY) |
| `UN_RADARR_0_URL` | Auto-computed | Unpackerr's Radarr URL (auto-uses RADARR__SERVER__PORT and URLBASE) |
| `UN_SONARR_0_API_KEY` | Auto-synced | Unpackerr's Sonarr API key (auto-uses SONARR__AUTH__APIKEY) |
| `UN_SONARR_0_URL` | Auto-computed | Unpackerr's Sonarr URL (auto-uses SONARR__SERVER__PORT and URLBASE) |

### Volumes

| Mount Point | Purpose | Required |
|-------------|---------|----------|
| `/config` | Configuration files for all services | Yes |
| `/media` | Media library (movies/TV shows) and downloads | Yes |

The download location and media are colocated so that moving file from the download folder to their final destination can be done efficiently by the file system. Crossing mount boundary would require doing full read and write even when a move operation would be enough.

## Using with Podman Quadlet

Quadlet allows you to define containers as systemd units. Here's an example Quadlet file:

### File: `~/.config/containers/systemd/starr.container`

```ini
[Unit]
Description=Starr - Radarr, Sonarr, Prowlarr, Unpackerr
After=network-online.target
Wants=network-online.target

[Container]
Image=starr:latest
ContainerName=starr
Exec=/sbin/init
Restart=on-failure:5
RestartSec=10s

# Port mappings
PublishPort=7878:7878
PublishPort=8989:8989
PublishPort=9696:9696

# Volume mounts
Volume=%h/containers/starr/config:/config:Z
Volume=%h/containers/starr/media:/media:Z

# Environment variables (override defaults as needed)
Environment="RADARR__AUTH__APIKEY=your-custom-radarr-key"
Environment="SONARR__AUTH__APIKEY=your-custom-sonarr-key"
Environment="RADARR__AUTH__ENABLED=true"
Environment="SONARR__AUTH__ENABLED=true"
Environment="RADARR__AUTH__METHOD=Forms"
Environment="SONARR__AUTH__METHOD=Forms"

# Resource limits (optional)
MemoryLimit=2G
CPUShares=1024

[Service]
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=default.target
```

### Using the Quadlet File

1. **Enable and start**:
   ```bash
   systemctl --user enable starr.container
   systemctl --user start starr.container
   ```

2. **Check status**:
   ```bash
   systemctl --user status starr.container
   ```

3. **View logs**:
   ```bash
   journalctl --user -u starr.container -f
   ```

4. **Stop**:
   ```bash
   systemctl --user stop starr.container
   ```

### Quadlet Variable Substitution

The Quadlet example above uses:
- `%h` = User's home directory
- `Z` = SELinux label bind mount (use on SELinux systems, remove on others)

Adjust paths as needed for your setup.

## Advanced Configuration

### Changing Service Ports

To run services on different ports:

```bash
podman run -d \
  --name starr \
  -e RADARR__SERVER__PORT=7879 \
  -e SONARR__SERVER__PORT=8990 \
  -p 7879:7879 \
  -p 8990:8990 \
  -p 9696:9696 \
  -v config:/config \
  -v media:/media \
  starr
```

### Using URL Bases (Behind Reverse Proxy)

If running behind a reverse proxy with path-based routing:

```bash
podman run -d \
  --name starr \
  -e RADARR__SERVER__URLBASE=/radarr \
  -e SONARR__SERVER__URLBASE=/sonarr \
  -e PROWLARR__SERVER__URLBASE=/prowlarr \
  -p 7878:7878 \
  -p 8989:8989 \
  -p 9696:9696 \
  -v config:/config \
  -v media:/media \
  starr
```

Then access at:
- `http://reverse-proxy/radarr`
- `http://reverse-proxy/sonarr`
- `http://reverse-proxy/prowlarr`

### Enabling Authentication

To enable API key authentication:

```bash
podman run -d \
  --name starr \
  -e RADARR__AUTH__ENABLED=true \
  -e RADARR__AUTH__APIKEY=your-secure-key-here \
  -e SONARR__AUTH__ENABLED=true \
  -e SONARR__AUTH__APIKEY=your-secure-key-here \
  -e RADARR__AUTH__METHOD=ApiKey \
  -e SONARR__AUTH__METHOD=ApiKey \
  -p 7878:7878 \
  -p 8989:8989 \
  -p 9696:9696 \
  -v config:/config \
  -v media:/media \
  starr
```

## Directory Structure

Inside the container:

```
/opt/
├── Radarr/          # Radarr binaries and libraries
├── Sonarr/          # Sonarr binaries and libraries
└── Prowlarr/        # Prowlarr binaries and libraries

/config/            # Config files (persistent, mounted volume)
├── radarr/
├── sonarr/
├── prowlarr/
└── unpackerr/

/usr/bin/
└── unpackerr        # Unpackerr binary

/etc/systemd/system/
└── radarr.service, sonarr.service, prowlarr.service

/usr/lib/systemd/system/
└── unpackerr.service
```

## Important Notes

1. **File Deduplication**: Identical libraries across services use symlinks, saving ~137MB. This is safe and transparent.

2. **Systemd Integration**: Services run under systemd, enabling proper dependency management and clean shutdowns.

3. **Authentication Methods**:
   - `External`: Delegates auth to reverse proxy (default)
   - `Forms`: Traditional form-based login
   - `Basic`: Browser pop-up
   - `None`: No authentication (not recommended for public access)

4. **API Key Format**: Must be a 32-character hexadecimal string (e.g., `c59b53c7cb39521ead0c0dbc1a61a401`)

5. **First Run**: On first start, services may take 30-60 seconds to initialize. Check logs with `podman logs starr`.

## Troubleshooting

### Services not starting

```bash
# Check service status inside container
podman exec starr systemctl status

# Check specific service
podman exec starr systemctl status radarr
```

### Can't reach services

Verify port mappings:
```bash
podman port starr
```

### Configuration not applying

Environment variables set at container creation time. To change them:
```bash
podman stop starr
podman rm starr
podman run -d ... -e NEW_VAR=value ... starr
```

Or with Quadlet: Edit the `.container` file and restart:
```bash
systemctl --user daemon-reload
systemctl --user restart starr.container
```

## Building from Source

```bash
podman build -t starr:latest -f ubi.dockerfile .
```

The build includes:
- Multi-stage Docker build for minimal final size
- File deduplication for shared libraries
- Pre-enabled systemd services
- Optimized for production use

## License

This container image includes Radarr, Sonarr, Prowlarr, and Unpackerr. See their respective project pages for licensing information.
