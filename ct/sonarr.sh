#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/jsinme/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://sonarr.tv/

APP="Sonarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/lib/sonarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Migration check for existing root installations
  CURRENT_USER=$(grep "^User=" /etc/systemd/system/sonarr.service 2>/dev/null | cut -d= -f2 || true)
  if [[ -z "$CURRENT_USER" || "$CURRENT_USER" == "root" ]]; then
    echo ""
    msg_info "Current installation runs as root"
    read -r -p "Migrate to dedicated sonarr user? <y/N> " migrate
    if [[ "${migrate,,}" =~ ^(y|yes)$ ]]; then
      read -r -p "Enter UID for sonarr user [default: 1000]: " USER_UID
      USER_UID=${USER_UID:-1000}

      if ! id -u sonarr &>/dev/null; then
        groupadd -g "$USER_UID" sonarr
        useradd -u "$USER_UID" -g "$USER_UID" -r -s /usr/sbin/nologin -d /var/lib/sonarr sonarr
        msg_ok "Created sonarr user (UID: ${USER_UID})"
      fi

      # Update service file to run as sonarr
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
      systemctl daemon-reload

      chown -R sonarr:sonarr /opt/Sonarr /var/lib/sonarr
      msg_ok "Migrated to sonarr user"
      MIGRATED_USER="yes"
    fi
  fi

  msg_info "Stopping Service"
  systemctl stop sonarr
  msg_ok "Stopped Service"

  msg_info "Updating Sonarr"
  curl -fsSL "https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux&arch=x64" -o "SonarrV4.tar.gz"
  tar -xzf SonarrV4.tar.gz
  rm -rf /opt/Sonarr
  mv Sonarr /opt
  rm -rf SonarrV4.tar.gz

  # Fix ownership if running as dedicated user
  if grep -q "^User=sonarr" /etc/systemd/system/sonarr.service 2>/dev/null; then
    chown -R sonarr:sonarr /opt/Sonarr
  fi
  msg_ok "Updated Sonarr"

  msg_info "Starting Service"
  systemctl start sonarr
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8989${CL}"
echo ""
echo -e "${INFO}${YW} If you chose the dedicated sonarr user (for NFS compatibility):${CL}"
echo -e "${TAB}  1. Add to /etc/subuid and /etc/subgid on Proxmox host:"
echo -e "${TAB}     root:1000:1"
echo -e "${TAB}  2. Add to /etc/pve/lxc/<id>.conf (adjust if you used a different UID):"
echo -e "${TAB}     lxc.idmap: u 0 100000 1000"
echo -e "${TAB}     lxc.idmap: g 0 100000 1000"
echo -e "${TAB}     lxc.idmap: u 1000 1000 1"
echo -e "${TAB}     lxc.idmap: g 1000 1000 1"
echo -e "${TAB}     lxc.idmap: u 1001 101001 64535"
echo -e "${TAB}     lxc.idmap: g 1001 101001 64535"
echo -e "${TAB}  3. Fix ownership from Proxmox host after adding idmap:"
echo -e "${TAB}     pct stop <id> && pct mount <id>"
echo -e "${TAB}     chown -R 1000:1000 /var/lib/lxc/<id>/rootfs/opt/Sonarr"
echo -e "${TAB}     chown -R 1000:1000 /var/lib/lxc/<id>/rootfs/var/lib/sonarr"
echo -e "${TAB}     pct unmount <id> && pct start <id>"
echo -e "${TAB}  4. Create matching user on NAS with same UID"
echo ""
