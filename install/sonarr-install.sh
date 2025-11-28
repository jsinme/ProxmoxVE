#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://sonarr.tv/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

USE_SONARR_USER="no"
read -r -p "Use dedicated sonarr user instead of root? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  DEFAULT_UID=1000
  read -r -p "${TAB3}Enter UID for sonarr user [default: ${DEFAULT_UID}]: " USER_UID
  USER_UID=${USER_UID:-$DEFAULT_UID}
  msg_info "Creating sonarr user"
  groupadd -g "$USER_UID" sonarr
  useradd -u "$USER_UID" -g "$USER_UID" -r -s /usr/sbin/nologin -d /var/lib/sonarr sonarr
  msg_ok "Created sonarr user (UID: ${USER_UID})"
  USE_SONARR_USER="yes"
fi

msg_info "Installing Dependencies"
$STD apt install -y sqlite3
msg_ok "Installed Dependencies"

msg_info "Installing Sonarr v4"
mkdir -p /var/lib/sonarr/
chmod 775 /var/lib/sonarr/
curl -fsSL "https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux&arch=x64" -o "SonarrV4.tar.gz"
tar -xzf SonarrV4.tar.gz
mv Sonarr /opt
rm -rf SonarrV4.tar.gz

msg_ok "Installed Sonarr v4"

if [[ "${USE_SONARR_USER}" == "yes" ]]; then
  msg_info "Setting ownership"
  chown -R sonarr:sonarr /opt/Sonarr /var/lib/sonarr
  msg_ok "Set ownership"
fi

msg_info "Creating Service"
if [[ "${USE_SONARR_USER}" == "yes" ]]; then
  cat <<EOF >/etc/systemd/system/sonarr.service
[Unit]
Description=Sonarr Daemon
After=syslog.target network.target

[Service]
User=sonarr
Group=sonarr
UMask=0002
Type=simple
ExecStart=/opt/Sonarr/Sonarr -nobrowser -data=/var/lib/sonarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
else
  cat <<EOF >/etc/systemd/system/sonarr.service
[Unit]
Description=Sonarr Daemon
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/opt/Sonarr/Sonarr -nobrowser -data=/var/lib/sonarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
fi
systemctl enable -q --now sonarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
