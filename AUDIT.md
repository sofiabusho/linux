#### Installation

##### Ask the auditee to start their virtual machine and log in.

###### Does the machine boot to a text console login, rather than to a graphical session?

###### Is this a minimal install, with no desktop environment installed?

#### Storage

##### Ask the auditee to run `lsblk` and `lvs`, then compare the output with the layout documented in their runbook.

###### Are there separate logical volumes for `/`, `/home`, `/var`, and swap?

###### Does the layout on the machine match the layout described in the runbook?

##### Ask the auditee to explain the size they chose for `/var` and what would happen if it filled up.

###### Did the auditee give a reason based on what the volume is used for, rather than restating the number?

##### Ask the auditee to extend a logical volume and grow its filesystem live, following their own documented procedure.

###### Did the volume and its filesystem both grow, with the data on that volume still intact afterward?

#### Networking

##### Ask the auditee to show the file or files where the static IP is configured, then to run `ping -c 3 deb.debian.org`.

###### Is the address configured in a system configuration file rather than through a graphical tool?

###### Does the machine resolve DNS and reach the internet?

#### Service

##### Ask the auditee to run `systemctl status` on their custom service.

###### Is the service both `enabled` and `active`?

##### Ask the auditee to find the main process ID of the service, stop it with a plain `kill <pid>`, then check the status again. SIGTERM is what a plain `kill` sends, and `systemd` counts it as a clean exit, so only a service with `Restart=always` comes back.

###### Did the service restart automatically?

##### Ask the auditee to show the service output with `journalctl`.

###### Is the service logging to the journal?

#### Understanding

##### Ask the auditee to run `systemd-analyze blame` and explain one of the slowest units, then to explain the difference between `enabled` and `active`. (`enabled` means the unit starts at boot. `active` means it is running now.)

###### Could the auditee explain what that unit does in their own words?

###### Was the explanation of `enabled` versus `active` correct?

#### Runbook

##### Read the auditee's `README.md`.

###### Does the runbook contain the volume sizing justification, the grow procedure, the network configuration, and the boot report?

###### Is the runbook detailed enough that you believe you could rebuild this machine from it without asking the auditee a single question?