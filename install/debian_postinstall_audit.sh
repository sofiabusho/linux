#!/bin/bash
## Audit-oriented postinstall for Debian (VirtualBox unattended).
## Expects to run without chroot initially (debian-installer late_command).

if [ "$1" = "--direct" ]; then
    MY_TARGET="/"
else
    MY_TARGET="/target"
fi
MY_LOGFILE="${MY_TARGET}/var/log/vboxpostinstall.log"
MY_CHROOT_CDROM="/cdrom"
MY_CDROM_NOCHROOT="/cdrom"
MY_EXITCODE=0

if [ "$1" = "--need-target-bash" ]; then
    if [ -z "${LD_LIBRARY_PATH}" ]; then
        LD_LIBRARY_PATH="${MY_TARGET}/lib"
    fi
    for x in \
        ${MY_TARGET}/lib \
        ${MY_TARGET}/usr/lib \
        ${MY_TARGET}/lib/*linux-gnu/ \
        ${MY_TARGET}/usr/lib/*linux-gnu/ \
        ; do
        if [ -e "$x" ]; then LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${x}"; fi
    done
    export LD_LIBRARY_PATH
    PATH="${PATH}:${MY_TARGET}/bin:${MY_TARGET}/usr/bin:${MY_TARGET}/sbin:${MY_TARGET}/usr/sbin"
    export PATH
    shift
    echo "** Relaunching with target bash" >> "${MY_LOGFILE}"
    exec "${MY_TARGET}/bin/bash" "$0" "$@"
fi

log_command() {
    echo "--------------------------------------------------" >> "${MY_LOGFILE}"
    echo "** Executing: $*" >> "${MY_LOGFILE}"
    "$@" 2>&1 | tee -a "${MY_LOGFILE}"
    MY_TMP_EXITCODE="${PIPESTATUS[0]}"
    if [ "${MY_TMP_EXITCODE}" != "0" ]; then
        echo "** exit code: ${MY_TMP_EXITCODE}" | tee -a "${MY_LOGFILE}"
        MY_EXITCODE=1
    fi
}

log_command_in_target() {
    log_command chroot "${MY_TARGET}" "$@"
}

echo "******************************************************************************" >> "${MY_LOGFILE}"
echo "** Audit postinstall started: $(date -R)" >> "${MY_LOGFILE}"

if [ -f /lib/chroot-setup.sh ]; then
    . /lib/chroot-setup.sh
    chroot_setup || true
fi

if [ ! -d "${MY_TARGET}${MY_CHROOT_CDROM}" ]; then
    mkdir -p "${MY_TARGET}${MY_CHROOT_CDROM}"
fi
if [ ! -f "${MY_TARGET}${MY_CHROOT_CDROM}/vboxpostinstall.sh" ]; then
    mount -o bind "${MY_CDROM_NOCHROOT}" "${MY_TARGET}${MY_CHROOT_CDROM}" || true
fi

# ---------------------------------------------------------------------------
# Static IP (VirtualBox NAT defaults: guest 10.0.2.15, gw 10.0.2.2)
# ---------------------------------------------------------------------------
IFACE="enp0s3"
# Prefer whatever primary iface debian-installer used, if detectable
if [ -r "${MY_TARGET}/etc/network/interfaces" ]; then
    FOUND=$(awk '/^allow-hotplug|^auto / && $2 !~ /lo/ { print $2; exit }' "${MY_TARGET}/etc/network/interfaces" || true)
    if [ -n "${FOUND}" ]; then IFACE="${FOUND}"; fi
fi

cat > "${MY_TARGET}/etc/network/interfaces" <<EOF
# Loopback
auto lo
iface lo inet loopback

# Primary NIC — static addressing (documented in README.md)
auto ${IFACE}
iface ${IFACE} inet static
    address 10.0.2.15
    netmask 255.255.255.0
    gateway 10.0.2.2
    dns-nameservers 8.8.8.8 1.1.1.1
EOF
echo "** Wrote static network config for ${IFACE}" | tee -a "${MY_LOGFILE}"

# ---------------------------------------------------------------------------
# Remove desktop bits if any slipped in (audit: text console only)
# ---------------------------------------------------------------------------
log_command_in_target bash -c '
export DEBIAN_FRONTEND=noninteractive
apt-get -y purge "gdm3" "lightdm" "sddm" "gdm" \
  "gnome-shell" "gnome-session" "task-gnome-desktop" \
  "task-desktop" "xserver-xorg" "x11-common" 2>/dev/null || true
apt-get -y autoremove --purge 2>/dev/null || true
systemctl set-default multi-user.target 2>/dev/null || true
# Ensure getty on tty1
systemctl enable getty@tty1.service 2>/dev/null || true
'

# ---------------------------------------------------------------------------
# Custom systemd service with Restart=always (audit requirement)
# ---------------------------------------------------------------------------
cat > "${MY_TARGET}/usr/local/bin/audit-heartbeat.sh" <<'EOF'
#!/bin/bash
# Simple long-running service that logs to the journal via stdout.
while true; do
  echo "audit-heartbeat: alive at $(date -Is)"
  sleep 15
done
EOF
chmod 755 "${MY_TARGET}/usr/local/bin/audit-heartbeat.sh"

cat > "${MY_TARGET}/etc/systemd/system/audit-heartbeat.service" <<'EOF'
[Unit]
Description=Audit heartbeat service (Restart=always demo)
After=network.target
Documentation=file:///root/README-SERVICE.txt

[Service]
Type=simple
ExecStart=/usr/local/bin/audit-heartbeat.sh
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > "${MY_TARGET}/root/README-SERVICE.txt" <<'EOF'
Service: audit-heartbeat.service
Purpose: demonstrates a custom unit that is enabled at boot and restarts on kill.
EOF

log_command_in_target systemctl daemon-reload
log_command_in_target systemctl enable audit-heartbeat.service

# ---------------------------------------------------------------------------
# Boot report snapshot helpers (for runbook)
# ---------------------------------------------------------------------------
cat > "${MY_TARGET}/usr/local/bin/boot-report.sh" <<'EOF'
#!/bin/bash
echo "=== hostname ==="; hostname
echo "=== uname ==="; uname -a
echo "=== lsblk ==="; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
echo "=== lvs ==="; sudo lvs -a -o lv_name,vg_name,lv_size,lv_attr
echo "=== vgs ==="; sudo vgs
echo "=== ip ==="; ip -br addr
echo "=== systemd default ==="; systemctl get-default
echo "=== audit-heartbeat ==="; systemctl is-enabled audit-heartbeat.service; systemctl is-active audit-heartbeat.service || true
EOF
chmod 755 "${MY_TARGET}/usr/local/bin/boot-report.sh"

# Ensure sshd enabled
log_command_in_target systemctl enable ssh.service

# Cleanup chroot setup
if [ -n "${MY_HAVE_CHROOT_SETUP}" ]; then
    chroot_cleanup || true
fi

echo "** Audit postinstall finished exit=${MY_EXITCODE}: $(date -R)" >> "${MY_LOGFILE}"
exit "${MY_EXITCODE}"
