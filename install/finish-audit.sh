#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq cloud-guest-utils >/dev/null 2>&1 || apt-get install -y -qq cloud-utils >/dev/null 2>&1 || true
echo 1 > /sys/block/sda/device/rescan || true
growpart /dev/sda 2
pvresize /dev/sda2
echo BEFORE_GROW
vgs
lvs -o lv_name,lv_size,vg_name
df -h /home
lvextend -L +1G /dev/vg0/home
resize2fs /dev/vg0/home
echo AFTER_GROW
vgs
lvs -o lv_name,lv_size,vg_name
df -h /home
pid=$(systemctl show -p MainPID --value audit-heartbeat)
echo OLD_PID=$pid
kill "$pid"
sleep 4
pid2=$(systemctl show -p MainPID --value audit-heartbeat)
echo NEW_PID=$pid2
systemctl is-active audit-heartbeat
