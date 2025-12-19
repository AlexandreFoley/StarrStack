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

# Define PassEnvironment variables based on app
case "$app" in
radarr)
    pass_env="RADARR__APP__INSTANCENAME RADARR__APP__THEME RADARR__APP__LAUNCHBROWSER RADARR__AUTH__APIKEY RADARR__AUTH__ENABLED RADARR__AUTH__METHOD RADARR__AUTH__REQUIRED RADARR__LOG__LEVEL RADARR__LOG__FILTERSENTRYEVENTS RADARR__LOG__ROTATE RADARR__LOG__SIZELIMIT RADARR__LOG__SQL RADARR__LOG__CONSOLELEVEL RADARR__LOG__CONSOLEFORMAT RADARR__LOG__ANALYTICSENABLED RADARR__LOG__SYSLOGSERVER RADARR__LOG__SYSLOGPORT RADARR__LOG__SYSLOGLEVEL RADARR__LOG__DBENABLED RADARR__POSTGRES__HOST RADARR__POSTGRES__PORT RADARR__POSTGRES__USER RADARR__POSTGRES__PASSWORD RADARR__POSTGRES__MAINDB RADARR__POSTGRES__LOGDB RADARR__SERVER__URLBASE RADARR__SERVER__BINDADDRESS RADARR__SERVER__PORT RADARR__SERVER__ENABLESSL RADARR__SERVER__SSLPORT RADARR__SERVER__SSLCERTPATH RADARR__SERVER__SSLCERTPASSWORD RADARR__UPDATE__MECHANISM RADARR__UPDATE__AUTOMATICALLY RADARR__UPDATE__SCRIPTPATH RADARR__UPDATE__BRANCH"
    ;;
sonarr)
    pass_env="SONARR__APP__INSTANCENAME SONARR__APP__THEME SONARR__APP__LAUNCHBROWSER SONARR__AUTH__APIKEY SONARR__AUTH__ENABLED SONARR__AUTH__METHOD SONARR__AUTH__REQUIRED SONARR__LOG__LEVEL SONARR__LOG__FILTERSENTRYEVENTS SONARR__LOG__ROTATE SONARR__LOG__SIZELIMIT SONARR__LOG__SQL SONARR__LOG__CONSOLELEVEL SONARR__LOG__CONSOLEFORMAT SONARR__LOG__ANALYTICSENABLED SONARR__LOG__SYSLOGSERVER SONARR__LOG__SYSLOGPORT SONARR__LOG__SYSLOGLEVEL SONARR__LOG__DBENABLED SONARR__POSTGRES__HOST SONARR__POSTGRES__PORT SONARR__POSTGRES__USER SONARR__POSTGRES__PASSWORD SONARR__POSTGRES__MAINDB SONARR__POSTGRES__LOGDB SONARR__SERVER__URLBASE SONARR__SERVER__BINDADDRESS SONARR__SERVER__PORT SONARR__SERVER__ENABLESSL SONARR__SERVER__SSLPORT SONARR__SERVER__SSLCERTPATH SONARR__SERVER__SSLCERTPASSWORD SONARR__UPDATE__MECHANISM SONARR__UPDATE__AUTOMATICALLY SONARR__UPDATE__SCRIPTPATH SONARR__UPDATE__BRANCH"
    ;;
prowlarr)
    pass_env="PROWLARR__APP__INSTANCENAME PROWLARR__APP__THEME PROWLARR__APP__LAUNCHBROWSER PROWLARR__AUTH__APIKEY PROWLARR__AUTH__ENABLED PROWLARR__AUTH__METHOD PROWLARR__AUTH__REQUIRED PROWLARR__LOG__LEVEL PROWLARR__LOG__FILTERSENTRYEVENTS PROWLARR__LOG__ROTATE PROWLARR__LOG__SIZELIMIT PROWLARR__LOG__SQL PROWLARR__LOG__CONSOLELEVEL PROWLARR__LOG__CONSOLEFORMAT PROWLARR__LOG__ANALYTICSENABLED PROWLARR__LOG__SYSLOGSERVER PROWLARR__LOG__SYSLOGPORT PROWLARR__LOG__SYSLOGLEVEL PROWLARR__LOG__DBENABLED PROWLARR__SERVER__URLBASE PROWLARR__SERVER__BINDADDRESS PROWLARR__SERVER__PORT PROWLARR__SERVER__ENABLESSL PROWLARR__SERVER__SSLPORT PROWLARR__SERVER__SSLCERTPATH PROWLARR__SERVER__SSLCERTPASSWORD PROWLARR__UPDATE__MECHANISM PROWLARR__UPDATE__AUTOMATICALLY PROWLARR__UPDATE__SCRIPTPATH PROWLARR__UPDATE__BRANCH"
    ;;
*)
    pass_env=""
    ;;
esac

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
PassEnvironment=$pass_env
[Install]
WantedBy=multi-user.target
EOF

echo "Install complete"

# Exit
exit 0
