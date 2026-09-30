# Debian Server Runbook

Rebuild notes for the audit VM. Follow this document alone to recreate the machine.

## Credentials

| Account | Password |
|---------|----------|
| `s0meuan` (sudo) | `debian` |
| `root` | `debian` |

Hostname: `debian`  
SSH from Windows host: `ssh -p 2222 s0meuan@127.0.0.1`  
(VirtualBox NAT port-forward host `2222` → guest `22`.)

---

## Installation summary

- Hypervisor: Oracle VirtualBox 7.x on Windows (x86-64)
- Guest: Debian 13 (Trixie), **minimal / no desktop**
- Default target: `multi-user.target` (text console on tty1)
- Disk: 30 GiB VDI, SATA controller with **2 ports** (disk + empty DVD)
- RAM: 2048 MiB, CPUs: 2, NIC: NAT + SSH forward

Unattended install sources (kept in this repo):

- `install/debian_preseed_lvm.cfg` — LVM recipe, ssh-server only
- `install/debian_postinstall_audit.sh` — static IP + `audit-heartbeat` service

---

## Storage layout

### Design

| Volume | Mount | Size (approx) | Why |
|--------|-------|---------------|-----|
| `/boot` | `/boot` | ~487 MiB (ext4, non-LVM) | Kernels/initramfs outside LVM |
| `vg0/root` | `/` | ~4.8 GiB | OS + packages; kept modest |
| `vg0/swap` | swap | ~1 GiB | RAM pressure / hibernate headroom |
| `vg0/home` | `/home` | ~3.9 GiB (after demo grow) | User data isolated from `/` |
| `vg0/var` | `/var` | ~16 GiB | **Logs, apt cache, journals, service data** grow here |
| VG free | — | ~4 GiB | Reserved so volumes can be grown live |

### Why `/var` is large

`/var` holds apt caches (`/var/cache/apt`), systemd journals (`/var/log/journal`), package logs, and runtime state. Filling `/var` typically breaks package installs and logging first — services may fail to write state — while `/` and `/home` can remain usable. Isolating `/var` on its own LV limits blast radius and lets you grow that volume without touching others.

### Expected `lsblk` / `lvs` (representative)

```text
NAME          SIZE TYPE FSTYPE      MOUNTPOINT
sda            30G disk
├─sda1        487M part ext4        /boot
└─sda2       29.5G part LVM2_member
  ├─vg0-root  4.8G lvm  ext4        /
  ├─vg0-swap  976M lvm  swap        [SWAP]
  ├─vg0-home  3.9G lvm  ext4        /home
  └─vg0-var    16G lvm  ext4        /var
```

```text
LV    VG  LSize
home  vg0 ~3.9g
root  vg0 ~4.8g
swap  vg0 ~1.0g
var   vg0 ~16g
```

Volume group name: **`vg0`**.

Verify on the machine:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
sudo lvs
sudo vgs
```

---

## Growing a logical volume live

Prerequisite: free extents in the VG (`sudo vgs` shows `VFree` > 0).  
If the VG is full, expand the VDI on the host, boot the guest, then:

```bash
sudo growpart /dev/sda 2
sudo pvresize /dev/sda2
```

### Grow procedure (example: `/home` +1 GiB)

```bash
# 1) Extend the LV
sudo lvextend -L +1G /dev/vg0/home

# 2) Grow the filesystem (ext4 supports online grow)
sudo resize2fs /dev/vg0/home

# 3) Confirm
df -h /home
sudo lvs
```

Data on the volume remains intact; the filesystem is remounted/grown in place (no umount required for ext4 online grow).

---

## Networking

Static addressing is configured in **`/etc/network/interfaces`** (not a GUI tool):

```text
auto lo
iface lo inet loopback

auto enp0s3
iface enp0s3 inet static
    address 10.0.2.15
    netmask 255.255.255.0
    gateway 10.0.2.2
    dns-nameservers 8.8.8.8 1.1.1.1
```

These values match VirtualBox **NAT** defaults (guest `10.0.2.15`, gateway `10.0.2.2`).

Apply / check:

```bash
sudo systemctl restart networking   # or: sudo ifdown enp0s3 && sudo ifup enp0s3
ip -br addr
ping -c 3 deb.debian.org
```

---

## Custom service: `audit-heartbeat`

| Item | Value |
|------|--------|
| Unit | `/etc/systemd/system/audit-heartbeat.service` |
| Script | `/usr/local/bin/audit-heartbeat.sh` |
| Restart policy | `Restart=always` |
| Logging | stdout → journal |

```bash
systemctl status audit-heartbeat
systemctl is-enabled audit-heartbeat   # enabled = starts at boot
systemctl is-active audit-heartbeat    # active  = running now
journalctl -u audit-heartbeat -n 20 --no-pager
```

### Restart-on-kill check

```bash
pid=$(systemctl show -p MainPID --value audit-heartbeat)
kill "$pid"          # SIGTERM — clean exit; Restart=always brings it back
sleep 3
systemctl is-active audit-heartbeat
systemctl show -p MainPID --value audit-heartbeat   # new PID
```

---

## Boot report

Helper on the guest: `boot-report.sh` (if present) or run manually after login:

```bash
hostname
uname -a
systemctl get-default          # expect: multi-user.target
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
sudo lvs
sudo vgs
ip -br addr
systemctl is-enabled audit-heartbeat
systemctl is-active audit-heartbeat
systemd-analyze blame | head
```

### Boot notes

- Text console login on `tty1` (no graphical display manager).
- Default target is `multi-user.target`.
- After install, boot order should be **Hard Disk first**; DVD empty.

Shutdown from the CLI (project requirement):

```bash
sudo poweroff
```

---

## Rebuild checklist

1. Create VirtualBox VM (Debian 64-bit, 2 GiB RAM, 2 CPUs, 30 GiB disk, SATA **portcount=2**).
2. Attach Debian netinst ISO; add NAT rule `2222→22`.
3. Run unattended install with `install/debian_preseed_lvm.cfg` + `install/debian_postinstall_audit.sh`.
4. After first boot: confirm text login, `lsblk`/`lvs`, static IP, `ping deb.debian.org`, service enabled/active.
5. Ensure VG free space (resize VDI + `growpart`/`pvresize` if needed); practice `lvextend` + `resize2fs`.
6. Document any size changes you make back into this README.

---

## Audit mapping

| Audit topic | Where it is satisfied |
|-------------|------------------------|
| Text console / no desktop | `multi-user.target`, no gdm/gnome |
| LVs for `/`, `/home`, `/var`, swap | `vg0` layout above |
| `/var` sizing rationale | Storage section |
| Live LV + filesystem grow | Growing section |
| Static IP in config file | `/etc/network/interfaces` |
| Internet / DNS | `ping -c 3 deb.debian.org` |
| Custom service enabled+active | `audit-heartbeat` |
| Survives `kill <pid>` | `Restart=always` |
| Journal logging | `journalctl -u audit-heartbeat` |
| Runbook rebuildable | this file |
