#!/bin/bash
# Script Name: Arr Install Script for dnf package manager.
# copied from https://github.com/BWBama85/fedora-plex-and-arrstack-ansible-playbook
# should allow me to easily build an image from ubi-init
scriptversion="1.0.0"
scriptdate="2023-08-17"

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

if [ $# -lt 3 ]; then
    echo "Usage: $0 <app_name> <app_uid> <app_guid>"
    exit 1
fi

app="$1"
app_uid="$2"
app_guid="$3"

case $app in
lidarr)
    app_port="8686"
    app_prereq="curl sqlite chromaprint-tools mediainfo"
    app_umask="0002"
    branch="master"
    break
    ;;
prowlarr)
    app_port="9696"
    app_prereq="curl sqlite"
    app_umask="0002"
    branch="master"
    break
    ;;
radarr)
    app_port="7878"
    app_prereq="curl sqlite"
    app_umask="0002"
    branch="master"
    break
    ;;
readarr)
    app_port="8787"
    app_prereq="curl sqlite"
    app_umask="0002"
    branch="develop"
    break
    ;;
whisparr)
    app_port="6969"
    app_prereq="curl sqlite"
    app_umask="0002"
    branch="nightly"
    break
    ;;
sonarr)
    app_port="8989"
    app_prereq="curl sqlite"
    app_umask="0002"
    break
    ;;
quit)
    exit 0
    ;;
*)
    echo "Invalid option $REPLY"
    ;;
esac

# Constants
installdir="/opt"
bindir="${installdir}/${app^}"
datadir="/config/$app/"
app_bin=${app^}

# Create User / Group as needed
if [ "$app_guid" != "$app_uid" ]; then
    getent group "$app_guid" &>/dev/null || groupadd "$app_guid"
fi
getent passwd "$app_uid" &>/dev/null || adduser --system --no-create-home --gid "$app_guid" "$app_uid"

if ! getent group "$app_guid" | grep -qw "$app_uid"; then
    usermod -a -G "$app_guid" "$app_uid"
fi

# Stop the App if running
if systemctl is-active "$app" &>/dev/null; then
    systemctl stop "$app"
    systemctl disable "$app".service
    echo "Stopped existing $app"
fi

# Create Appdata Directory
mkdir -p "$datadir"
chown -R "$app_uid":"$app_guid" "$datadir"
chmod 775 "$datadir"
echo "Directories created"

# Download and install the App

# prerequisite packages
echo ""
echo "Installing pre-requisite Packages"
dnf update -y && dnf install -y --skip-broken $app_prereq
echo ""
ARCH=$(uname -m)
# get arch

if [ "$app" != "sonarr" ]; then
    dlbase="https://$app.servarr.com/v1/update/$branch/updatefile?os=linux&runtime=netcore"
    case "$ARCH" in
    "x86_64") DLURL="${dlbase}&arch=x64" ;;
    "armv7l") DLURL="${dlbase}&arch=arm" ;;
    "aarch64") DLURL="${dlbase}&arch=arm64" ;;
    *)
        echo "Arch not supported"
        exit 1
        ;;
    esac
elif [ "$app" == "sonarr" ]; then
    dlbase="https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux"
    case "$ARCH" in
    "x86_64") DLURL="${dlbase}&arch=x64" ;;
    "armv7l") DLURL="${dlbase}&arch=arm" ;;
    "aarch64") DLURL="${dlbase}&arch=arm64" ;;
    *)
        echo "Arch not supported"
        exit 1
        ;;
    esac
else
    echo "Something went wrong"
fi
echo ""
echo "Removing previous tarballs"
# -f to Force so we fail if it doesnt exist
rm -f "${app^}".*.tar.gz
echo ""
echo "Downloading $app from $DLURL"
wget -nv --content-disposition "$DLURL"
tar -xvzf "${app^}".*.tar.gz
echo ""
echo "Installation files downloaded and extracted"

# remove existing installs
echo "Removing existing installation"
# If you happen to run this script in the installdir the line below will delete the extracted files and cause the mv some lines below to fail.
rm -rf "$bindir"
echo "Installing..."
mv "${app^}" $installdir
chown "$app_uid":"$app_guid" -R "$bindir"
chmod 775 "$bindir"
rm -rf "${app^}.*.tar.gz"
# Ensure we check for an update in case user installs older version or different branch
touch "$datadir"/update_required
chown "$app_uid":"$app_guid" "$datadir"/update_required
echo "App Installed"
# Configure Autostart

# Remove any previous app .service
echo "default service file"
cat /etc/systemd/system/"$app".service || true
echo "Removing default service file"
rm -rf /etc/systemd/system/"$app".service

# Create app .service with correct user startup
echo "Creating service file"
cat <<EOF | tee /etc/systemd/system/"$app".service >/dev/null
[Unit]
Description=${app^} Daemon
After=syslog.target network.target
[Service]
User=$app_uid
Group=$app_guid
UMask=$app_umask
Type=simple
ExecStart=$bindir/$app_bin -nobrowser -data=$datadir
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

echo "Install complete"

# Exit
exit 0
