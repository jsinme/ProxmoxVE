#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/jsinme/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://radarr.video/

APP="Radarr"
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

  if [[ ! -d /var/lib/radarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Migration check for existing root installations
  CURRENT_USER=$(grep "^User=" /etc/systemd/system/radarr.service 2>/dev/null | cut -d= -f2)
  if [[ -z "$CURRENT_USER" || "$CURRENT_USER" == "root" ]]; then
    echo ""
    msg_info "Current installation runs as root"
    read -r -p "Migrate to dedicated radarr user? <y/N> " migrate
    if [[ "${migrate,,}" =~ ^(y|yes)$ ]]; then
      read -r -p "Enter UID for radarr user [default: 1000]: " USER_UID
      USER_UID=${USER_UID:-1000}

      if ! id -u radarr &>/dev/null; then
        groupadd -g "$USER_UID" radarr
        useradd -u "$USER_UID" -g "$USER_UID" -r -s /usr/sbin/nologin -d /var/lib/radarr radarr
        msg_ok "Created radarr user (UID: ${USER_UID})"
      fi

      # Update service file to run as radarr
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
      systemctl daemon-reload

      chown -R radarr:radarr /opt/Radarr /var/lib/radarr
      msg_ok "Migrated to radarr user"
      MIGRATED_USER="yes"
    fi
  fi

  if check_for_gh_release "Radarr" "Radarr/Radarr"; then
    msg_info "Stopping Service"
    systemctl stop radarr
    msg_ok "Stopped Service"

    rm -rf /opt/Radarr
    fetch_and_deploy_gh_release "Radarr" "Radarr/Radarr" "prebuild" "latest" "/opt/Radarr" "Radarr.master*linux-core-x64.tar.gz"
    chmod 775 /opt/Radarr

    # Fix ownership if running as dedicated user
    if grep -q "^User=radarr" /etc/systemd/system/radarr.service 2>/dev/null; then
      chown -R radarr:radarr /opt/Radarr
    fi

    msg_info "Starting Service"
    systemctl start radarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7878${CL}"
echo ""
echo -e "${INFO}${YW} If you chose the dedicated radarr user (for NFS compatibility):${CL}"
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
echo -e "${TAB}     chown -R 1000:1000 /var/lib/lxc/<id>/rootfs/opt/Radarr"
echo -e "${TAB}     chown -R 1000:1000 /var/lib/lxc/<id>/rootfs/var/lib/radarr"
echo -e "${TAB}     pct unmount <id> && pct start <id>"
echo -e "${TAB}  4. Create matching user on NAS with same UID"
echo ""
