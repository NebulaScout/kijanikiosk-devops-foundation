#!/bin/bash
# SCRIPT: provision_kijanikiosk.sh
# PURPOSE: Production-grade provisioning for KijaniKiosk infrastructure.


set -euo pipefail

# --- Configuration ---
readonly NGINX_PIN="1.28.3-2ubuntu1.6"
readonly NODEJS_MAJOR="20"
readonly SERVICES=("kk-api" "kk-payments" "kk-logs")
readonly SHARED_GROUP="kijanikiosk"
readonly BASE_DIR="/opt/kijanikiosk"
readonly CONFIG_DIR="$BASE_DIR/config"
readonly LOG_DIR="$BASE_DIR/shared/logs"

# --- Structured Logging ---
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warn() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; exit 1; }
log_check_error() { echo "[ERROR] $*" >&2; }

# --- Sudo wrapper (only used if not root) ---
SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

# --- Pre-flight Checks ---
check_prerequisites() {
    log_info "Running pre-flight checks..."

    [[ -f /etc/os-release ]] || log_error "Missing /etc/os-release"
    source /etc/os-release

	if [[ "$ID" == "ubuntu" ]]; then
	    log_info "Ubuntu detected: $VERSION_ID"
	else
	    log_error "Unsupported OS"
	    exit 1
	fi

    log_info "Detected Ubuntu ${VERSION_ID} (${VERSION_CODENAME})"

#    [[ -f /etc/kijanikiosk.provisioned ]] && \
 #       log_warn "Running in idempotent repair mode"
}

# --- Phase 1: Package Installation ---
install_packages() {
    log_info "Phase 1: Package Installation"

    $SUDO apt-get update -qq
    $SUDO apt-get install -y acl curl ufw logrotate gnupg


    if ! apt-mark showhold | grep -qx nginx; then
        apt-get install -y --no-install-recommends \
            "nginx=${NGINX_PIN}"
        apt-mark hold nginx
    fi

    if ! dpkg -l | grep -q "nginx.*$NGINX_PIN"; then
        $SUDO apt-get install -y "nginx=$NGINX_PIN"
        $SUDO apt-mark hold nginx
    fi

    # NodeSource repo
    if [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
        $SUDO mkdir -p /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
            | $SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    fi

    if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_MAJOR}.x nodistro main" \
            | $SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null
        $SUDO apt-get update -qq
    fi

    if ! command -v node &>/dev/null || ! node -v | grep -q "^v${NODEJS_MAJOR}"; then
        $SUDO apt-get install -y nodejs
        $SUDO apt-mark hold nodejs
    fi
}

# --- Users & Groups ---
setup_users_groups() {
    log_info "Phase 2: Creating Service Accounts"

    getent group "$SHARED_GROUP" >/dev/null || \
        $SUDO groupadd --system "$SHARED_GROUP"

    for user in "${SERVICES[@]}"; do
        if ! id "$user" &>/dev/null; then
            $SUDO useradd --system \
                --no-create-home \
                --shell /usr/sbin/nologin \
                --gid "$SHARED_GROUP" \
                "$user"
        else
            $SUDO usermod --shell /usr/sbin/nologin --gid "$SHARED_GROUP" "$user" || true
        fi
    done
}

# --- Directories ---
setup_directories() {
    log_info "Phase 3: Directory Structure"

    $SUDO install -d -m 750 -o kk-api -g kk-api "$BASE_DIR/api"
    $SUDO install -d -m 750 -o kk-payments -g kk-payments "$BASE_DIR/payments"
    $SUDO install -d -m 750 -o kk-logs -g kk-logs "$BASE_DIR/logs"

    $SUDO install -d -m 750 -o root -g "$SHARED_GROUP" "$CONFIG_DIR"
    $SUDO install -d -m 2770 -o kk-logs -g "$SHARED_GROUP" "$LOG_DIR"

    # Config ACLs
    $SUDO setfacl -b "$CONFIG_DIR"
    $SUDO setfacl -m u::rwx,g::rx,o::--- "$CONFIG_DIR"
    $SUDO setfacl -d -m u::rwx,g::r--,o::--- "$CONFIG_DIR"

    # Shared logs ACLs
    $SUDO setfacl -b "$LOG_DIR"
    $SUDO setfacl -m u:kk-api:wx,u:kk-payments:rx "$LOG_DIR"
    $SUDO setfacl -k "$LOG_DIR"
    $SUDO setfacl -d -m u:kk-api:rwX "$LOG_DIR"
    $SUDO setfacl -d -m u:kk-payments:rX "$LOG_DIR"
    $SUDO setfacl -d -m g:$SHARED_GROUP:rwX "$LOG_DIR"
    $SUDO setfacl -d -m o::--- "$LOG_DIR"

    log_info "Directories have been set up"
}

# --- Systemd ---
create_systemd_units() {
    log_info "Phase 4: Systemd Unit Files"

    write_unit_file() {
        local path="$1"
        local tmp

        tmp=$(mktemp)

        cat > "$tmp"

        if [[ -f "$path" ]] && diff -q "$tmp" "$path" >/dev/null 2>&1; then
            rm -f "$tmp"
            log_info "$(basename "$path") unchanged — skipping"
            return
        fi

        sudo mv "$tmp" "$path"
        log_info "$(basename "$path") written"
    }

    # --- kk-api ---
    write_unit_file "/etc/systemd/system/kk-api.service" <<EOF
[Unit]
Description=KijaniKiosk API
After=network.target

[Service]
User=kk-api
Group=kk-api
EnvironmentFile=$CONFIG_DIR/api.env
ExecStart=/usr/bin/node $BASE_DIR/api/server.js
Restart=on-failure

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
SystemCallArchitectures=native

ReadWritePaths=$BASE_DIR/api $LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

    # --- kk-payments ---
    write_unit_file "/etc/systemd/system/kk-payments.service" <<EOF
[Unit]
Description=KijaniKiosk Payments
After=network.target kk-api.service
Wants=kk-api.service

[Service]
User=kk-payments
Group=kk-payments
EnvironmentFile=$CONFIG_DIR/payments.env
ExecStart=/usr/bin/node $BASE_DIR/payments/processor.js
Restart=on-failure

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true

ReadWritePaths=$BASE_DIR/payments $LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

    # --- kk-logs ---
    write_unit_file "/etc/systemd/system/kk-logs.service" <<EOF
[Unit]
Description=KijaniKiosk Logs
After=network.target

[Service]
User=kk-logs
Group=kk-logs
EnvironmentFile=$CONFIG_DIR/logs.env
ExecStart=/usr/bin/node $BASE_DIR/logs/aggregator.js
Restart=on-failure

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
SystemCallArchitectures=native

ReadWritePaths=$BASE_DIR/logs $LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

    # Reload + enable
    sudo systemctl daemon-reload

    for svc in "${SERVICES[@]}"; do
        if systemctl is-enabled "$svc.service" &>/dev/null; then
            log_info "$svc.service already enabled — skipping"
        else
            sudo systemctl enable "$svc.service"
            log_info "$svc.service enabled"
        fi
    done
}

# --- Firewall ---
configure_firewall() {
    log_info "Phase 5: Firewall Configuration"

    $SUDO ufw --force reset
    $SUDO ufw default deny incoming
    $SUDO ufw default allow outgoing
    
    # $SUDO ufw status | grep -q "Status: active" || $SUDO ufw --force enable


    $SUDO ufw allow 22/tcp comment 'Allow SSH for remote administration'
    $SUDO ufw allow 80/tcp comment 'Allow HTTP for public web traffic'
    $SUDO ufw allow in on lo to any port 3001 comment 'Allow local nginx to access payments service via loopback'
    $SUDO ufw allow from 10.0.1.0/24 to any port 3001 proto tcp comment 'Allow monitoring subnet to access payments health endpoint'
    $SUDO ufw deny 3001/tcp comment 'Deny external access to internal payments service'
    
    $SUDO ufw --force enable

    if sudo ufw status | grep -q "Status: active"; then
        log_info "UFW enabled successfully"
    else
        log_error "UFW failed to activate"
    fi
}

# --- Phase 7: Journal Persistence & Log Rotation ---
setup_logging() {
    log_info "Phase 7: Journal Persistence & Log Rotation"

    # --- Journald Persistent Storage ---
    $SUDO mkdir -p /var/log/journal

    $SUDO sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
    $SUDO sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf

    $SUDO systemctl restart systemd-journald

    log_info "journald configured for persistent storage 500MB cap"

    # --- Logrotate Config ---
    local logrotate_file="/etc/logrotate.d/kijanikiosk"

    $SUDO tee "$logrotate_file" >/dev/null <<EOF
$LOG_DIR/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 kk-logs $SHARED_GROUP
    sharedscripts
    postrotate
        systemctl restart kk-logs.service >/dev/null 2>&1 || true
    endscript
}
EOF

    log_info "logrotate configuration written"

    # --- Verification ---
    if logrotate --debug /etc/logrotate.conf >/dev/null 2>&1; then
        log_info "logrotate configuration verification passed"
    else
        log_error "logrotate configuration verification failed"
    fi
}

# --- Phase 8: Monitoring Health Checks ---
setup_health_checks() {
    log_info "Phase 8: Monitoring Health Checks"

    local health_dir="$BASE_DIR/health"
    local health_file="$health_dir/last-provision.json"

    $SUDO mkdir -p "$health_dir"

    # --- Port Checks ---
    local api_status payments_status logs_status

    api_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3000" 2>/dev/null && echo '"ok"' || echo '"down"')
    payments_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3001" 2>/dev/null && echo '"ok"' || echo '"down"')
    logs_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3002" 2>/dev/null && echo '"ok"' || echo '"down"')

    # --- Write JSON ---
    printf '{"timestamp":"%s","kk-api":%s,"kk-payments":%s,"kk-logs":%s}\n' \
        "$(date -Is)" "$api_status" "$payments_status" "$logs_status" \
        | $SUDO tee "$health_file" >/dev/null

    # --- Permissions ---
    $SUDO chown kk-logs:$SHARED_GROUP "$health_file"
    $SUDO chmod 640 "$health_file"

    # --- Validation (file must exist, content may be "down") ---
    if [[ -f "$health_file" ]]; then
        log_info "Health check file created: $health_file"
    else
        log_error "Health check file missing"
    fi
}

verify_installation() {
    log_info "Running full system verification..."

    local failed=0

    check() {
        local name="$1"
        shift

        if "$@"; then
            echo "[PASS] $name"
        else
            echo "[FAIL] $name"
            ((failed++))
        fi
    }

    # --- Phase 1–6 Checks ---
    check "Nginx installed" bash -c "dpkg -l | grep -q nginx"

    for user in "${SERVICES[@]}"; do
        check "User exists: $user" id "$user"
    done

    check "kk-api enabled" systemctl is-enabled kk-api.service
    check "kk-payments enabled" systemctl is-enabled kk-payments.service
    check "kk-logs enabled" systemctl is-enabled kk-logs.service

    # --- Phase 7 Checks ---
    check "journald persistent" grep -q "^Storage=persistent" /etc/systemd/journald.conf
    check "journald capped" grep -q "^SystemMaxUse=500M" /etc/systemd/journald.conf
    check "logrotate valid" logrotate --debug /etc/logrotate.conf >/dev/null 2>&1

    # --- Phase 8 Checks ---
    local health_file="$BASE_DIR/health/last-provision.json"

    check "health file exists" test -f "$health_file"
    check "health file readable" test -r "$health_file"
    check "health file has content" grep -q "kk-api" "$health_file"

    # --- Final Result ---
    if [[ $failed -gt 0 ]]; then
        log_error "$failed checks failed"
    else
        log_info "All verification checks passed"
    fi
}


# --- Main ---
main() {
    check_prerequisites
    install_packages
    setup_users_groups
    setup_directories
    create_systemd_units
    configure_firewall
    setup_logging
    setup_health_checks
    verify_installation

    log_info "Provisioning completed successfully."
}

main "$@"
