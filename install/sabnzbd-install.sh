#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster) | Co-Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://sabnzbd.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

USE_SABNZBD_USER="no"
read -r -p "Use dedicated sabnzbd user instead of root? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  DEFAULT_UID=1000
  read -r -p "${TAB3}Enter UID for sabnzbd user [default: ${DEFAULT_UID}]: " USER_UID
  USER_UID=${USER_UID:-$DEFAULT_UID}
  groupadd -g "$USER_UID" sabnzbd
  useradd -u "$USER_UID" -g "$USER_UID" -r -s /usr/sbin/nologin -d /opt/sabnzbd sabnzbd
  msg_ok "Created sabnzbd user (UID: ${USER_UID})"
  USE_SABNZBD_USER="yes"
fi

msg_info "Installing Dependencies"
$STD apt install -y \
  par2 \
  p7zip-full
msg_ok "Installed Dependencies"

export UV_PYTHON_INSTALL_DIR="/opt/uv-python"
PYTHON_VERSION="3.13" setup_uv

msg_info "Setup Unrar"
cat <<EOF >/etc/apt/sources.list.d/non-free.sources
Types: deb
URIs: http://deb.debian.org/debian/
Suites: trixie
Components: non-free 
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
$STD apt update
$STD apt install -y unrar
msg_ok "Setup Unrar"

fetch_and_deploy_gh_release "sabnzbd-org" "sabnzbd/sabnzbd" "prebuild" "latest" "/opt/sabnzbd" "SABnzbd-*-src.tar.gz"

msg_info "Installing SABnzbd"
$STD uv venv /opt/sabnzbd/venv
$STD uv pip install -r /opt/sabnzbd/requirements.txt --python=/opt/sabnzbd/venv/bin/python
msg_ok "Installed SABnzbd"

if [[ "$USE_SABNZBD_USER" == "yes" ]]; then
  msg_info "Setting Ownership"
  chown -R sabnzbd:sabnzbd /opt/sabnzbd
  msg_ok "Set Ownership"
fi

read -r -p "Would you like to install par2cmdline-turbo? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  mv /usr/bin/par2 /usr/bin/par2.old
  fetch_and_deploy_gh_release "par2cmdline-turbo" "animetosho/par2cmdline-turbo" "prebuild" "latest" "/usr/bin/" "*-linux-amd64.zip"
fi

msg_info "Creating Service"
if [[ "$USE_SABNZBD_USER" == "yes" ]]; then
  cat <<EOF >/etc/systemd/system/sabnzbd.service
[Unit]
Description=SABnzbd
After=network.target

[Service]
WorkingDirectory=/opt/sabnzbd
ExecStart=/opt/sabnzbd/venv/bin/python SABnzbd.py -s 0.0.0.0:7777
Restart=always
User=sabnzbd
Group=sabnzbd
UMask=0002

[Install]
WantedBy=multi-user.target
EOF
else
  cat <<EOF >/etc/systemd/system/sabnzbd.service
[Unit]
Description=SABnzbd
After=network.target

[Service]
WorkingDirectory=/opt/sabnzbd
ExecStart=/opt/sabnzbd/venv/bin/python SABnzbd.py -s 0.0.0.0:7777
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
fi
systemctl enable -q --now sabnzbd
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
