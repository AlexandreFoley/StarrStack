# Quadlet Usage Guide

This directory contains the Quadlet units for StarrStack:

- `starrstack/starrstack.pod`
- `starrstack/starr.container`
- `starrstack/qbittorrent.container`

The units are meant to be copied into `~/.config/containers/systemd/` and managed with `systemctl --user`.

## Install The Quadlet Units

Copy the contained `starrstack` folder into your user Quadlet folder:

```bash
mkdir -p ~/.config/containers/systemd
cp -r quadlet/starrstack ~/.config/containers/systemd/
```

After copying, reload the user systemd daemon so Quadlet regenerates the services:

```bash
systemctl --user daemon-reload
```

The copied units create these services:

- `starrstack-pod.service`
- `starr.service`
- `qbittorrent.service`

## Create The Required Podman Secrets

The container files expect these Podman secrets to exist:

- `radarr_apikey`
- `sonarr_apikey`
- `prowlarr_apikey`
- `webui_password`

The three API keys can be generated on the spot with the commands below. For qBittorrent, choose your password, username is starruser, then create the matching secrets with those values.
If you choose to change the qbittorrent username, don't forget to change it in both container files.

Create them from stdin, one at a time:

```bash
head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n\r' | podman secret create radarr_apikey -
head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n\r' | podman secret create sonarr_apikey -
head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n\r' | podman secret create prowlarr_apikey -
printf '%s' 'your-qbittorrent-webui-password' | podman secret create webui_password -
```

If you rotate a secret later, recreate it with `--replace` and restart the affected service.

Start the stack with:

```bash
systemctl --user start starrstack-pod.service
```

## Optional qBittorrent VPN Setup

The qBittorrent image also supports WireGuard-based VPN settings. For a Private Internet Access setup, follow the same pattern shown in the Hotio WireGuard reference for [qBittorrent](https://hotio.dev/containers/qbittorrent/#wireguard).

If you want qBittorrent to use PIA, add these extra settings to `qbittorrent.container`:

These options go in the `[Container]` section of the file.

```ini
HostName=container-name.internal
AddCapability=NET_ADMIN

Environment=VPN_ENABLED=true
Environment=VPN_CONF=wg0
Environment=VPN_PROVIDER=pia
Environment=VPN_LAN_NETWORK=192.168.0.0/16
Environment=VPN_LAN_LEAK_ENABLED=false
Environment=VPN_EXPOSE_PORTS_ON_LAN=
Environment=VPN_AUTO_PORT_FORWARD=true
Environment=VPN_PORT_REDIRECTS=
Environment=VPN_HEALTHCHECK_ENABLED=false
Environment=VPN_NAMESERVERS=
Environment=VPN_INTERFACE_PREFIXES=
Environment=VPN_PIA_PREFERRED_REGION=
Environment=VPN_PIA_DIP_TOKEN=
Environment=VPN_PIA_PORT_FORWARD_PERSIST=false
Environment=PRIVOXY_ENABLED=false
Environment=UNBOUND_ENABLED=false
Environment=UNBOUND_NAMESERVERS=
Secret=pia_user,type=env,target=VPN_PIA_USER
Secret=pia_pass,type=env,target=VPN_PIA_PASS
```

Create the two PIA secrets before starting the service:

```bash
printf '%s' 'your-pia-username' | podman secret create pia_user -
printf '%s' 'your-pia-password' | podman secret create pia_pass -
```

`VPN_LAN_NETWORK` should match your home LAN, and `VPN_AUTO_PORT_FORWARD=true` is the useful default for PIA. If you use a different VPN provider or region, update those values accordingly.

## Media Mount Override

By default the Quadlet units mount the local `mounts/media` directory from the copied folder. If you want to replace that with a different media source, edit `starr.container` and change the media volume to a host mountpoint, for example:

```ini
Volume=/mnt/media:/media:rw
```

This is the better option when the media storage lives on a NAS or other network-backed filesystem. Keep the container bind mount pointed at a stable local mountpoint, and let `systemd` handle the remote filesystem mount underneath it.

### NAS Example With `systemd` Mounts

Use a dedicated mountpoint such as `/mnt/media` and create matching user units:

`~/.config/systemd/user/mnt-media.mount`

```ini
[Unit]
Description=NAS media mount for StarrStack

[Mount]
What=//nas.example.lan/media
Where=/mnt/media
Type=cifs
Options=credentials=%h/.config/smb/media.cred,iocharset=utf8,uid=%U,gid=%U,vers=3.1.1

[Install]
WantedBy=default.target
```

`~/.config/systemd/user/mnt-media.automount`

```ini
[Unit]
Description=Automount NAS media for StarrStack

[Automount]
Where=/mnt/media

[Install]
WantedBy=default.target
```

Enable the automount and the quadlet stack:

```bash
systemctl --user daemon-reload
systemctl --user enable --now mnt-media.automount
systemctl --user enable --now starrstack-pod.service
```

With this setup, the NAS is mounted on demand the first time the container accesses `/mnt/media`. That avoids boot-time stalls and keeps the stack usable even when the NAS is briefly offline.

### Notes For NAS Backends

- Keep the media path stable. If the NAS mount point changes, update the `Volume=` line in `starr.container`.
- Use `automount` so `systemd` can recover cleanly after network drops.
- For NFS, change `Type=` to `nfs` and replace `Options=` with the appropriate NFS mount options.
- For local disks or non-network storage, a plain mount unit without `automount` is usually enough.

## Operational Tips

- Use `journalctl --user -u starrstack-pod.service -f` to follow stack logs.
- Use `systemctl --user status starr.service qbittorrent.service` to check the generated services.
- If a secret changes, recreate it first, then restart the affected unit.
- If you move the Quadlet folder after installation, run `systemctl --user daemon-reload` again.