#!/bin/bash
# ============================================================
#  rTorrent + libtorrent — Compile from Source
#  Versions: libtorrent 0.15.7 + rTorrent 0.15.7 (latest stable)
#  Tested on: Ubuntu 20.04 / 22.04 / 24.04
#  Usage: sudo bash compile_rtorrent.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[→]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "Run as root: sudo bash compile_rtorrent.sh"

BUILD_DIR="/tmp/rtorrent-build"
INSTALL_PREFIX="/usr/local"
NPROC=$(nproc)

# ── Version picker ────────────────────────────────────────────
echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${CYAN}   rTorrent — Compile from Source               ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Select a version to compile:\n"
echo -e "  ${BOLD}Stable (recommended)${NC}"
echo -e "   1) 0.15.7  — Sep 2025  ${GREEN}[latest stable]${NC} Most compatible with Flood"
echo -e "   2) 0.15.6  — Aug 2025  IPv4/6 handling improvements"
echo -e "   3) 0.15.5  — Jun 2025  DNS dedup buffer, libcurl socket fixes"
echo -e "   4) 0.15.4  — Jun 2025  HTTP reuse, curl moved to libtorrent"
echo -e "   5) 0.15.3  — May 2025  Session parallel save"
echo -e "   6) 0.15.2  — Mar 2025  First stable with Flood API v11 compat"
echo ""
echo -e "  ${BOLD}Development (bleeding edge)${NC}"
echo -e "   7) 0.16.6  — Jan 2026  ${YELLOW}[dev latest]${NC} Multi-threaded HTTP/session"
echo -e "   8) 0.16.5  — Dec 2025  ${YELLOW}[dev]${NC}        Replaces buggy 0.16.3/4"
echo ""
echo -e "  ${BOLD}Legacy${NC}"
echo -e "   9) 0.10.0  — Sep 2024  Return from 5-year hiatus"
echo -e "  10) 0.9.8   — Jul 2019  Same as apt. Very old, battle-tested"
echo ""

while true; do
  read -rp "  Enter number [1-10] (default: 1): " CHOICE
  CHOICE="${CHOICE:-1}"
  case "$CHOICE" in
    1)  RTORRENT_VER="0.15.7"; break ;;
    2)  RTORRENT_VER="0.15.6"; break ;;
    3)  RTORRENT_VER="0.15.5"; break ;;
    4)  RTORRENT_VER="0.15.4"; break ;;
    5)  RTORRENT_VER="0.15.3"; break ;;
    6)  RTORRENT_VER="0.15.2"; break ;;
    7)  RTORRENT_VER="0.16.6"; break ;;
    8)  RTORRENT_VER="0.16.5"; break ;;
    9)  RTORRENT_VER="0.10.0"; break ;;
    10) RTORRENT_VER="0.9.8";  break ;;
    *)  echo -e "  ${RED}Invalid choice. Enter a number between 1 and 10.${NC}" ;;
  esac
done

LIBTORRENT_VER="$RTORRENT_VER"

echo ""
echo -e "  ${GREEN}Selected: rTorrent ${RTORRENT_VER}${NC}"
echo ""
read -rp "  Proceed with compilation? [Y/n]: " CONFIRM
[[ "${CONFIRM,,}" == "n" ]] && { echo "Aborted."; exit 0; }

echo ""
echo -e "  libtorrent : ${LIBTORRENT_VER}"
echo -e "  rTorrent   : ${RTORRENT_VER}"
echo -e "  Threads    : ${NPROC} (detected cores)"
echo -e "  Prefix     : ${INSTALL_PREFIX}"
echo ""

# ── 1. Remove old apt rtorrent to avoid conflicts ─────────────
info "Removing apt rtorrent if installed..."
systemctl stop rtorrent 2>/dev/null || true
apt-get remove -y rtorrent 2>/dev/null || true
log "Old rtorrent removed"

# ── 2. Install build dependencies ─────────────────────────────
info "Installing build dependencies..."
apt-get update -qq

# xmlrpc-c package name differs between Ubuntu versions
XMLRPC_PKG="libxmlrpc-c3-dev"
apt-cache show "$XMLRPC_PKG" &>/dev/null || XMLRPC_PKG="libxmlrpc-core-c3-dev"
apt-cache show "$XMLRPC_PKG" &>/dev/null || { warn "xmlrpc-c dev package not found — will compile without it"; XMLRPC_PKG=""; }

apt-get install -y \
  build-essential \
  automake \
  autoconf \
  libtool \
  pkg-config \
  git \
  wget \
  curl \
  libssl-dev \
  libcurl4-openssl-dev \
  libncurses5-dev \
  libncursesw5-dev \
  libsigc++-2.0-dev \
  screen \
  mediainfo \
  >> /tmp/rtorrent-build.log 2>&1

[[ -n "$XMLRPC_PKG" ]] && {
  apt-get install -y "$XMLRPC_PKG" >> /tmp/rtorrent-build.log 2>&1 \
    && log "Build dependencies installed (xmlrpc-c: $XMLRPC_PKG)" \
    || { warn "Could not install $XMLRPC_PKG — will compile without xmlrpc-c"; XMLRPC_PKG=""; }
} || log "Build dependencies installed (no xmlrpc-c)"

# ── 3. Prepare build directory ────────────────────────────────
info "Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
log "Build directory: $BUILD_DIR"

# ── 4. Download libtorrent ────────────────────────────────────
info "Downloading libtorrent ${LIBTORRENT_VER}..."
wget -q "https://github.com/rakshasa/rtorrent/releases/download/v${RTORRENT_VER}/libtorrent-${LIBTORRENT_VER}.tar.gz"
tar xzf "libtorrent-${LIBTORRENT_VER}.tar.gz"
log "libtorrent downloaded and extracted"

# ── 5. Compile libtorrent ─────────────────────────────────────
info "Compiling libtorrent (using ${NPROC} threads)..."
cd "${BUILD_DIR}/libtorrent-${LIBTORRENT_VER}"
autoreconf -ivf >> /tmp/rtorrent-build.log 2>&1
./configure \
  --prefix="${INSTALL_PREFIX}" \
  --disable-debug \
  >> /tmp/rtorrent-build.log 2>&1
make -j"${NPROC}" >> /tmp/rtorrent-build.log 2>&1
make install >> /tmp/rtorrent-build.log 2>&1
ldconfig
log "libtorrent ${LIBTORRENT_VER} compiled and installed"

# ── 6. Download rTorrent ──────────────────────────────────────
info "Downloading rTorrent ${RTORRENT_VER}..."
cd "$BUILD_DIR"
wget -q "https://github.com/rakshasa/rtorrent/releases/download/v${RTORRENT_VER}/rtorrent-${RTORRENT_VER}.tar.gz"
tar xzf "rtorrent-${RTORRENT_VER}.tar.gz"
log "rTorrent downloaded and extracted"

# ── 7. Compile rTorrent ───────────────────────────────────────
info "Compiling rTorrent (using ${NPROC} threads)..."
cd "${BUILD_DIR}/rtorrent-${RTORRENT_VER}"
autoreconf -ivf >> /tmp/rtorrent-build.log 2>&1
if [[ -n "$XMLRPC_PKG" ]]; then
  ./configure \
    --prefix="${INSTALL_PREFIX}" \
    --disable-debug \
    --with-xmlrpc-c \
    >> /tmp/rtorrent-build.log 2>&1 && log "Configured with xmlrpc-c support" || {
      warn "xmlrpc-c configure flag failed — falling back without it"
      ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --disable-debug \
        >> /tmp/rtorrent-build.log 2>&1
    }
else
  warn "Compiling without xmlrpc-c (not available on this system)"
  ./configure \
    --prefix="${INSTALL_PREFIX}" \
    --disable-debug \
    >> /tmp/rtorrent-build.log 2>&1
fi
make -j"${NPROC}" >> /tmp/rtorrent-build.log 2>&1
make install >> /tmp/rtorrent-build.log 2>&1
ldconfig
log "rTorrent ${RTORRENT_VER} compiled and installed"

# ── 8. Verify installation ────────────────────────────────────
info "Verifying installation..."
RTORRENT_BIN=$(which rtorrent 2>/dev/null || echo "${INSTALL_PREFIX}/bin/rtorrent")
[[ -f "$RTORRENT_BIN" ]] || err "Binary not found at $RTORRENT_BIN"
# rTorrent prints version via -v or on startup — parse it from the binary directly
INSTALLED_VER=$("$RTORRENT_BIN" -v 2>&1 | head -1)
[[ -z "$INSTALLED_VER" || "$INSTALLED_VER" == *"invalid"* ]] &&   INSTALLED_VER=$(strings "$RTORRENT_BIN" 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | head -1)
[[ -z "$INSTALLED_VER" ]] && INSTALLED_VER="$RTORRENT_VER (from build)"
echo "  Installed: rTorrent $INSTALLED_VER"
echo "  Binary:    $RTORRENT_BIN"
log "rTorrent binary confirmed"

# ── 9. Create rtorrent user if not exists ─────────────────────
info "Setting up rtorrent user..."
if ! id rtorrent &>/dev/null; then
  useradd --system --shell /bin/bash --create-home rtorrent
  log "User 'rtorrent' created"
else
  log "User 'rtorrent' already exists"
fi

# ── 10. Create directories ────────────────────────────────────
info "Creating directories..."
mkdir -p /home/rtorrent/downloads /home/rtorrent/.session /var/run/rtorrent /var/log/rtorrent
chown -R rtorrent:rtorrent /home/rtorrent /var/run/rtorrent /var/log/rtorrent
log "Directories ready"

# ── 11. Write rTorrent config ─────────────────────────────────
info "Writing rTorrent config..."
cat > /home/rtorrent/.rtorrent.rc <<'EOF'
directory.default.set = /home/rtorrent/downloads
session.path.set      = /home/rtorrent/.session

network.port_range.set  = 50000-50000
network.port_random.set = no

throttle.global_up.max_rate.set   = 0
throttle.global_down.max_rate.set = 0
throttle.max_peers.normal.set = 100
throttle.max_peers.seed.set   = 50
throttle.max_uploads.set      = 15

network.scgi.open_local = /var/run/rtorrent/rtorrent.sock
schedule2 = socket_chmod,0,0,"execute.nothrow=chmod,770,/var/run/rtorrent/rtorrent.sock"

dht.mode.set         = auto
dht.port.set         = 6881
protocol.pex.set     = yes
trackers.use_udp.set = yes

log.open_file = "rtorrent", /var/log/rtorrent/rtorrent.log
log.add_output = "info", "rtorrent"
EOF
chown rtorrent:rtorrent /home/rtorrent/.rtorrent.rc
log "Config written"

# ── 12. Write systemd service ─────────────────────────────────
info "Writing systemd service..."
cat > /etc/systemd/system/rtorrent.service <<EOF
[Unit]
Description=rTorrent ${RTORRENT_VER} (compiled from source)
After=network.target

[Service]
Type=forking
User=rtorrent
ExecStartPre=/bin/mkdir -p /var/run/rtorrent
ExecStartPre=/bin/chown rtorrent:rtorrent /var/run/rtorrent
ExecStart=/usr/bin/screen -d -m -S rtorrent ${RTORRENT_BIN}
ExecStop=/usr/bin/screen -S rtorrent -X quit
Restart=on-failure
RestartSec=10
KillMode=none

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rtorrent
systemctl start rtorrent
sleep 4

RT_STATUS=$(systemctl is-active rtorrent)
[[ "$RT_STATUS" == "active" ]] && log "rTorrent service started" || {
  err "rTorrent failed to start — check: journalctl -u rtorrent -n 30"
}

# ── 13. Wait for socket ───────────────────────────────────────
info "Waiting for SCGI socket..."
for i in {1..15}; do
  [[ -S /var/run/rtorrent/rtorrent.sock ]] && { log "Socket ready"; break; }
  echo -n "."
  sleep 2
done
echo ""
[[ ! -S /var/run/rtorrent/rtorrent.sock ]] && err "Socket never appeared"
chmod 770 /var/run/rtorrent/rtorrent.sock

# ── 14. Install Node.js + Flood (if not already installed) ────
if ! command -v flood &>/dev/null; then
  info "Installing Node.js LTS..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >> /tmp/rtorrent-build.log 2>&1
  apt-get install -y nodejs >> /tmp/rtorrent-build.log 2>&1
  log "Node.js $(node -v) installed"

  info "Installing Flood..."
  npm install -g flood >> /tmp/rtorrent-build.log 2>&1
  log "Flood installed"
else
  log "Flood already installed at $(which flood)"
fi

# ── 15. Write Flood service ───────────────────────────────────
info "Writing Flood systemd service..."
FLOOD_BIN=$(which flood)
cat > /etc/systemd/system/flood.service <<EOF
[Unit]
Description=Flood Web UI
After=network.target rtorrent.service

[Service]
Type=simple
User=rtorrent
Environment=HOME=/home/rtorrent
ExecStart=${FLOOD_BIN} --port 3000 --host 0.0.0.0 --allowedpath /home/rtorrent/downloads
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flood
systemctl start flood
sleep 4

FL_STATUS=$(systemctl is-active flood)
[[ "$FL_STATUS" == "active" ]] && log "Flood service started" || {
  warn "Flood failed — check: journalctl -u flood -n 30"
}

# ── 16. Firewall ──────────────────────────────────────────────
info "Configuring firewall..."
command -v ufw &>/dev/null && ufw status | grep -q "active" && {
  ufw allow 3000/tcp comment "Flood Web UI"
  ufw allow 50000/tcp comment "rTorrent"
  ufw allow 50000/udp comment "rTorrent UDP"
  log "UFW rules added"
} || warn "UFW not active — open ports 3000 and 50000 in your provider's firewall"

# ── Summary ───────────────────────────────────────────────────
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Done! rTorrent ${RTORRENT_VER} compiled & running     ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}rTorrent version:${NC} rTorrent ${RTORRENT_VER} (compiled from source)"
echo -e "  ${CYAN}Binary:${NC}           $RTORRENT_BIN"
echo -e "  ${CYAN}Flood UI:${NC}         http://${SERVER_IP}:3000"
echo ""
echo -e "  ${YELLOW}In Flood browser setup:${NC}"
echo "    Client type  →  rTorrent"
echo "    Connection   →  Socket"
echo "    Socket path  →  /var/run/rtorrent/rtorrent.sock"
echo ""
echo -e "  ${YELLOW}Build log:${NC} /tmp/rtorrent-build.log"
echo ""

# Cleanup
rm -rf "$BUILD_DIR"
log "Build directory cleaned up"
