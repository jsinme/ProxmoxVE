#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://radarr.video/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

USE_RADARR_USER="no"
read -r -p "Use dedicated radarr user instead of root? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  DEFAULT_UID=1000
  read -r -p "${TAB3}Enter UID for radarr user [default: ${DEFAULT_UID}]: " USER_UID
  USER_UID=${USER_UID:-$DEFAULT_UID}
  msg_info "Creating radarr user"
  groupadd -g "$USER_UID" radarr
  useradd -u "$USER_UID" -g "$USER_UID" -r -s /usr/sbin/nologin -d /var/lib/radarr radarr
  msg_ok "Created radarr user (UID: ${USER_UID})"
  USE_RADARR_USER="yes"
fi

msg_info "Installing Dependencies"
$STD apt install -y sqlite3
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "Radarr" "Radarr/Radarr" "prebuild" "latest" "/opt/Radarr" "Radarr.master*linux-core-x64.tar.gz"

msg_info "Configuring Radarr"
mkdir -p /var/lib/radarr/
chmod 775 /var/lib/radarr/ /opt/Radarr/
if [[ "${USE_RADARR_USER}" == "yes" ]]; then
  chown -R radarr:radarr /opt/Radarr /var/lib/radarr
fi
msg_ok "Configured Radarr"

msg_info "Creating Service"
if [[ "${USE_RADARR_USER}" == "yes" ]]; then
  cat <<EOF >/etc/systemd/system/radarr.service
[Unit]
Description=Radarr Daemon
After=syslog.target network.target

[Service]
User=radarr
Group=radarr
UMask=0002
Type=simple
ExecStart=/opt/Radarr/Radarr -nobrowser -data=/var/lib/radarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
else
  cat <<EOF >/etc/systemd/system/radarr.service
[Unit]
Description=Radarr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Radarr/Radarr -nobrowser -data=/var/lib/radarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
fi
systemctl enable -q --now radarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
