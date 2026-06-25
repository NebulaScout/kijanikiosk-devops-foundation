## Challenge A: ProtectSystem=strict and the EnvironmentFile

**Conflict**
`ProtectSystem=strict` makes large parts of the filesystem (including `/etc`) read-only to the service process. However, services such as `kk-payments` require access to configuration files defined via `EnvironmentFile`. Earlier in the week, configuration files may have been placed under `/etc/kijanikiosk/`, which could become inaccessible depending on systemd restrictions.

**Options Considered**

1. Keep configuration under `/etc/kijanikiosk/` and relax systemd restrictions using directives such as `ReadWritePaths` or `ReadOnlyPaths`.
2. Move configuration files to a service-owned directory outside protected system paths (e.g., `/opt/kijanikiosk/config/`).
3. Disable `ProtectSystem=strict` (not acceptable due to security requirements).

**Decision**
Configuration files were moved to `/opt/kijanikiosk/config/`, and all services reference this path via `EnvironmentFile`.

**Justification**
This approach preserves the security guarantees of `ProtectSystem=strict` while ensuring services can still read their configuration. It avoids introducing exceptions that weaken the filesystem protection model and keeps all application-related data under a single controlled directory (`/opt/kijanikiosk`). This aligns with the principle of least privilege and simplifies operational management.

---

## Challenge B: The Monitoring User and ACL Defaults

**Conflict**
Phase 8 introduces a health check file at `/opt/kijanikiosk/health/last-provision.json`, written by the provisioning script running as root. However, both the monitoring system and a regular user (Amina) must read this file without requiring elevated privileges. The health directory was not part of the original access control model.

**Options Considered**

1. Change ownership of the health file to a shared user/group after creation.
2. Make the file world-readable (e.g., `chmod 644`).
3. Use group-based access with the existing `kijanikiosk` group.
4. Apply ACLs to explicitly grant read access to required users.

**Decision**
The `/opt/kijanikiosk/health/` directory is owned by `root:kijanikiosk` with permissions `750`, and files inside are created with `640`. The `kijanikiosk` group includes all relevant service users and the monitoring user. Default ACLs are applied to ensure new files inherit readable permissions for the group.

**Justification**
This approach maintains controlled access without overexposing sensitive data. World-readable permissions were avoided to reduce unnecessary exposure. Using the existing group structure ensures consistency with the access model defined earlier in the week, while ACL defaults guarantee future files remain accessible without manual intervention.

---

## Challenge C: logrotate postrotate and PrivateTmp

**Conflict**
The `logrotate` configuration requires a `postrotate` action to notify `kk-logs` to reopen its log files after rotation. The standard command `systemctl reload` assumes the service supports reload via `ExecReload`. However, `kk-logs` does not define `ExecReload`, and it runs with `PrivateTmp=true`, which isolates its temporary filesystem.

**Options Considered**

1. Use `systemctl reload kk-logs.service` (fails because no `ExecReload` is defined).
2. Add an `ExecReload` directive to the service unit.
3. Use `systemctl restart kk-logs.service`.
4. Use `kill -HUP` to signal the process manually.

**Decision**
The `postrotate` script uses:

```
systemctl restart kk-logs.service
```

**Justification**
Since the service does not support reload semantics, restart is the most reliable and systemd-compliant option. It ensures that file descriptors are cleanly reopened after log rotation. Adding a custom `ExecReload` would require modifying application behavior, which is outside the scope of infrastructure provisioning. The restart approach is simple, predictable, and consistent with systemd best practices.

---

## Challenge D: The Dirty VM and Package Holds

**Conflict**
The provisioning script runs on a system where packages may already be installed and potentially upgraded. Installing pinned versions (e.g., `nginx=1.28.3-2ubuntu1.6`) may trigger unintended downgrades. While `apt-mark hold` prevents upgrades, it does not fully protect against mismatched states if applied after installation.

**Options Considered**

1. Always force installation of pinned versions, allowing downgrades.
2. Skip installation if the package is already present.
3. Check installed versions and fail if they do not match the pinned versions.
4. Automatically downgrade to the pinned version.

**Decision**
Before installation, the script checks the currently installed version. If it matches the pinned version, installation is skipped. If it differs, the script fails with a clear error message requiring manual intervention.

**Justification**
Failing loudly avoids unintended downgrades, which could introduce instability or break dependencies. Automatic downgrades are risky in production environments and can lead to inconsistent states. This approach enforces strict version control while ensuring that deviations are explicitly reviewed and corrected by an operator. It prioritizes safety and predictability over convenience.

---

## Summary

Each integration challenge required balancing security, operability, and consistency. The final decisions prioritize:

* Strong isolation (`ProtectSystem=strict`)
* Controlled access via groups and ACLs
* Reliable service behavior using systemd-native mechanisms
* Safe package management through explicit version validation

All resolutions were validated through successful execution of the provisioning script and full system verification.
