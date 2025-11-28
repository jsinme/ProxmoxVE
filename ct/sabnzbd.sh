#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/jsinme/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster) | Co-Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://sabnzbd.org/

APP="SABnzbd"
var_tags="${var_tags:-downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
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

    if par2 --version | grep -q "par2cmdline-turbo"; then
        fetch_and_deploy_gh_release "par2cmdline-turbo" "animetosho/par2cmdline-turbo" "prebuild" "latest" "/usr/bin/" "*-linux-amd64.zip"
    fi

    if [[ ! -d /opt/sabnzbd ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    # Migration check for existing root installations
    CURRENT_USER=$(stat -c '%U' /opt/sabnzbd 2>/dev/null)
    if [[ "$CURRENT_USER" == "root" ]]; then
        echo ""
        msg_info "Current installation runs as root"
        read -r -p "${TAB3}Migrate to dedicated sabnzbd user? <y/N> " migrate
        if [[ "${migrate,,}" =~ ^(y|yes)$ ]]; then
            read -r -p "${TAB3}Enter UID for sabnzbd user [default: 1000]: " USER_UID
            USER_UID=${USER_UID:-1000}

            if ! id -u sabnzbd &>/dev/null; then
                groupadd -g "$USER_UID" sabnzbd
                useradd -u "$USER_UID" -g "$USER_UID" -r -s /usr/sbin/nologin -d /opt/sabnzbd sabnzbd
                msg_ok "Created sabnzbd user (UID: ${USER_UID})"
            fi

            # Update service file to run as sabnzbd
            if ! grep -q "^User=sabnzbd" /etc/systemd/system/sabnzbd.service; then
                sed -i 's/^User=root/User=sabnzbd/' /etc/systemd/system/sabnzbd.service
                sed -i '/^User=sabnzbd/a Group=sabnzbd' /etc/systemd/system/sabnzbd.service
                sed -i '/^Group=sabnzbd/a UMask=0002' /etc/systemd/system/sabnzbd.service
                systemctl daemon-reload
            fi

            chown -R sabnzbd:sabnzbd /opt/sabnzbd
            msg_ok "Migrated to sabnzbd user"
            MIGRATE_USER="sabnzbd"
        fi
    fi

    if check_for_gh_release "sabnzbd-org" "sabnzbd/sabnzbd"; then
        export UV_PYTHON_INSTALL_DIR="/opt/uv-python"
        PYTHON_VERSION="3.13" setup_uv
        systemctl stop sabnzbd
        cp -r /opt/sabnzbd /opt/sabnzbd_backup_$(date +%s)
        fetch_and_deploy_gh_release "sabnzbd-org" "sabnzbd/sabnzbd" "prebuild" "latest" "/opt/sabnzbd" "SABnzbd-*-src.tar.gz"

        if [[ ! -d /opt/sabnzbd/venv ]]; then
            msg_info "Migrating SABnzbd to uv virtual environment"
            $STD uv venv /opt/sabnzbd/venv
            msg_ok "Created uv venv at /opt/sabnzbd/venv"

            if grep -q "ExecStart=python3 SABnzbd.py" /etc/systemd/system/sabnzbd.service; then
                sed -i "s|ExecStart=python3 SABnzbd.py|ExecStart=/opt/sabnzbd/venv/bin/python SABnzbd.py|" /etc/systemd/system/sabnzbd.service
                systemctl daemon-reload
                msg_ok "Updated SABnzbd service to use uv venv"
            fi
        fi
        $STD uv pip install --upgrade pip --python=/opt/sabnzbd/venv/bin/python
        $STD uv pip install -r /opt/sabnzbd/requirements.txt --python=/opt/sabnzbd/venv/bin/python

        # Re-apply ownership after update
        if [[ -n "$MIGRATE_USER" ]] || [[ "$CURRENT_USER" == "sabnzbd" ]]; then
            chown -R sabnzbd:sabnzbd /opt/sabnzbd
            msg_ok "Applied ownership to sabnzbd user"
        fi

        systemctl start sabnzbd
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7777${CL}"
echo ""
echo -e "${INFO}${YW} If you chose the dedicated sabnzbd user (for NFS compatibility):${CL}"
echo -e "${TAB}  1. Add to /etc/subuid and /etc/subgid on Proxmox host:"
echo -e "${TAB}     root:1000:1"
echo -e "${TAB}  2. Add to /etc/pve/lxc/<id>.conf (adjust if you used a different UID):"
echo -e "${TAB}     lxc.idmap: u 0 100000 1000"
echo -e "${TAB}     lxc.idmap: g 0 100000 1000"
echo -e "${TAB}     lxc.idmap: u 1000 1000 1"
echo -e "${TAB}     lxc.idmap: g 1000 1000 1"
echo -e "${TAB}     lxc.idmap: u 1001 101001 64535"
echo -e "${TAB}     lxc.idmap: g 1001 101001 64535"
echo -e "${TAB}  3. Create matching user on NAS with same UID"
echo ""
echo -e "${TAB}  Note: If using a UID other than 1000, adjust the idmap ranges accordingly."
echo -e "${TAB}  The first range maps 0-(UID-1), the second maps your UID, the third maps (UID+1)-65535."
