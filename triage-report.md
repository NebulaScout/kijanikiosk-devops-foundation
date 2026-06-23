# KijaniKiosk API Server - Triage Report

**Date:** 22/06/2026
**Investigated by:** Richard Kabi
**Server:** `kijani-kiosk-api-01` (Ubuntu 22.04 LTS)
**Incident start (approximate):** 2026-06-22 16:46:10 UTC

## Summary
I found a clear memory-pressure incident on the VM, not a CPU saturation problem. The strongest root-cause signal is a Python process at PID 2644 consuming about 521 MB RSS and over 53% of system memory, with kernel logs confirming the OOM killer fired shortly after that process appeared. Response time degradation from about 120 ms to 480 ms lines up with that pressure window.

---

## Process and Resource State
The dominant process is `python3 -c ...` at PID 2644, using roughly 53.5% memory and only minimal CPU, so the bottleneck is memory exhaustion rather than compute load. 

* **Top Memory Consumers:**
  * `python3 -c ...` (PID 2644): ~53.5% MEM
  * `networkd-dispatcher` (PID 1453): ~1.8–1.9% MEM
  * `unattended-upgrade-shutdown` (PID 1543): ~1.8–1.9% MEM

The CPU is otherwise quiet; no process is showing sustained high CPU, so the latency increase is not explained by processor saturation.

---

## Filesystem and Disk
Disk space is not yet critical, though utilization is elevated. The main abnormality is the application log directory, which merits attention but is not the immediate trigger of the latency incident.

* **Partition `/dev/sda1` Status:**
  * **Total Size:** 3.8 GB
  * **Used:** 2.4 GB
  * **Free:** 1.4 GB
  * **Utilization:** 65%

* **Key Directory Highlight:** `/var/log/kijanikiosk` is currently at 271 MB. Other logs are comparatively small, making this the only filesystem item that stands out.

---

## Log Analysis

### Application Logs
Errors cluster around query, database, and connection failures. The app log shows error bursts beginning at `2024-01-15 04:07:55`, with another cluster around `06:22:18–06:22:28`, suggesting intermittent failure periods rather than a single one-off error.
* **Frequency/Type Count:** Repeated `Query`, `ECONNREFUSED`, and `Database` entries, plus single `Retry`, `Memory`, and `Connection` messages.

### System Logs
System logs are more decisive and capture the critical infrastructure failure points:
1. **Repeated kernel I/O errors** on `fd0`.
2. **Explicit OOM-killer event** at `2026-06-22 16:46:10`, where the Python process was killed after reaching about 517 MB anonymous RSS.

> **Note on Security:** There are no signs of unexpected authentication activity beyond normal SSH sessions originating from `10.96.192.1`, so login events do not appear relevant.

---

## Network and Service State
Port binding looks normal for a simple web host, with no signs of connection pileup or socket exhaustion:

* **Listeners:** SSH is listening on port `22` and HTTP on port `80`. No unexpected listeners detected.
* **Local Endpoint Verification:**
  * `curl http://localhost/`: Returns **HTTP 200** in about **0.0006 s** (web server itself is responding quickly at the root path).
  * `curl http://localhost/api/health`: Returns **HTTP 404** in about **0.0022 s** (suggests the health endpoint is missing or misrouted, but not slow).
* **TCP State:** Mostly healthy, with only a small number of established connections.

---

## Assessment
The best hypothesis is that a runaway or test Python process exhausted memory, triggered the kernel OOM killer, and pushed the VM into memory pressure severe enough to degrade API latency. 

The evidence fits together:
* The Python process owns most of the RAM.
* The kernel explicitly killed Python for out-of-memory (OOM).
* Application logs show `Memory`, `Database`, and `ECONNREFUSED` errors during the same general window.
* Response time degraded heavily from **120 ms to 480 ms** without any corresponding CPU spike. 

Disk usage is elevated in the application log directory, but that looks secondary; it does not explain the latency jump as well as the memory event does.

---

## Recommended Next Steps

1. **Remediate Process:** Stop and remove the offending Python process, then confirm whether it is an accidental workload, a test artifact, or a leaked background job.
2. **Implement Guardrails:** Review the application or service responsible for spawning that process and add memory limits, supervision, or container/systemd resource constraints so it cannot consume the node unchecked.
3. **Investigate Secondary Failures:** Investigate the `/var/log/kijanikiosk` directory growth and the `ECONNREFUSED` / `Database` errors to determine whether the memory event caused downstream service failures or if there is a separate database connectivity issue.