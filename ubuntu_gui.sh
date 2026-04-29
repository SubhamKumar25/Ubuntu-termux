#!/data/data/com.termux/files/usr/bin/bash

# =====================================================
#  Ubuntu 22.04 + XFCE4 GUI Installer for Termux
#  Optimized for Moto Tab 60 Pro via termux-x11
# =====================================================

time1="$(date +"%r")"

# ── Colors ──────────────────────────────────────────
RED='\x1b[38;5;203m'
YEL='\x1b[38;5;227m'
GRN='\x1b[38;5;83m'
CYN='\x1b[38;5;87m'
ORG='\x1b[38;5;214m'
RST='\e[0m'

log_info()  { printf "${ORG}[${time1}]${RST} ${GRN}[INFO]:${RST}    ${CYN}$1\n${RST}"; }
log_warn()  { printf "${ORG}[${time1}]${RST} ${YEL}[WARNING]:${RST} ${CYN}$1\n${RST}"; }
log_err()   { printf "${ORG}[${time1}]${RST} ${RED}[ERROR]:${RST}   ${CYN}$1\n${RST}"; }
log_step()  { printf "\n${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}\n${CYN}  ▶ $1${RST}\n${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}\n"; }

# ── Config ───────────────────────────────────────────
DIRECTORY=ubuntu-fs
UBUNTU_VERSION=22.04
ARCHITECTURE=arm64   # Moto Tab 60 Pro is always ARM64

# ── Step 1: Install Termux dependencies ─────────────
step_termux_deps() {
    log_step "Installing Termux dependencies"
    pkg update -y && pkg upgrade -y
    pkg install -y \
        proot \
        proot-distro \
        wget \
        tar \
        x11-repo \
        termux-x11-nightly \
        pulseaudio \
        virglrenderer-android
    log_info "Termux dependencies installed."
}

# ── Step 2: Download & extract Ubuntu rootfs ────────
step_download() {
    if [ -d "$DIRECTORY" ]; then
        log_warn "ubuntu-fs already exists. Skipping download."
        return
    fi

    [ -f "ubuntu.tar.gz" ] && rm -f ubuntu.tar.gz

    log_step "Downloading Ubuntu ${UBUNTU_VERSION} rootfs (ARM64)"
    wget "http://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_VERSION}-base-${ARCHITECTURE}.tar.gz" \
        --show-progress -q -O ubuntu.tar.gz
    log_info "Download complete."

    log_step "Extracting rootfs"
    mkdir -p "$DIRECTORY"
    tar -zxf ubuntu.tar.gz -C "$DIRECTORY" --exclude='dev' || :
    rm -f ubuntu.tar.gz
    log_info "Extraction complete."
}

# ── Step 3: Configure rootfs ────────────────────────
step_configure_rootfs() {
    log_step "Configuring Ubuntu rootfs for performance"

    local R="$DIRECTORY"

    # DNS
    printf "nameserver 8.8.8.8\nnameserver 8.8.4.4\n" > "$R/etc/resolv.conf"

    # Stub /usr/bin/groups
    echo -e "#!/bin/sh\nexit" > "$R/usr/bin/groups"
    chmod +x "$R/usr/bin/groups"

    # Locale — C.UTF-8 is fastest, skip locale-gen
    mkdir -p "$R/etc/default"
    cat > "$R/etc/default/locale" <<'EOF'
LANG=C.UTF-8
LC_ALL=C.UTF-8
EOF

    # APT performance config
    mkdir -p "$R/etc/apt/apt.conf.d"
    cat > "$R/etc/apt/apt.conf.d/99-mototab-perf" <<'EOF'
Acquire::Languages "none";
Acquire::GzipIndexes "true";
Acquire::CompressionTypes::Order:: "gz";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

    # Disable heavy services inside proot
    mkdir -p "$R/etc/systemd/system"
    for svc in snapd.service apt-daily.service apt-daily-upgrade.service motd-news.service NetworkManager.service; do
        ln -sf /dev/null "$R/etc/systemd/system/$svc" 2>/dev/null || true
    done

    log_info "Rootfs configuration done."
}

# ── Step 4: Create start script ─────────────────────
step_create_launcher() {
    log_step "Creating startubuntu.sh launcher"
    mkdir -p ubuntu-binds

    cat > startubuntu.sh <<- 'EOM'
#!/bin/bash
cd "$(dirname "$0")"
unset LD_PRELOAD

# Performance env
export MALLOC_ARENA_MAX=2
export PYTHONDONTWRITEBYTECODE=1
export JAVA_TOOL_OPTIONS="-Xmx512m"

DIRECTORY=ubuntu-fs

command="proot"
command+=" --link2symlink"
command+=" -0"
command+=" --kill-on-exit"
command+=" -r $DIRECTORY"

if [ -n "$(ls -A ubuntu-binds 2>/dev/null)" ]; then
    for f in ubuntu-binds/*; do
        . "$f"
    done
fi

command+=" -b /dev"
command+=" -b /proc"
command+=" -b /sys"
command+=" -b $DIRECTORY/tmp:/dev/shm"
command+=" -b /data/data/com.termux"
command+=" -b /:/host-rootfs"
command+=" -b /sdcard"
command+=" -b /storage"
command+=" -b /mnt"
command+=" -b /data/data/com.termux/files/usr/tmp:/tmp"
command+=" -w /root"
command+=" /usr/bin/env -i"
command+=" HOME=/root"
command+=" PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin"
command+=" TERM=$TERM"
command+=" LANG=C.UTF-8"
command+=" LC_ALL=C.UTF-8"
command+=" MALLOC_ARENA_MAX=2"
command+=" /bin/bash --login"

if [ -z "$1" ]; then
    exec $command
else
    $command -c "$@"
fi
EOM

    termux-fix-shebang startubuntu.sh
    chmod +x startubuntu.sh
    log_info "startubuntu.sh created."
}

# ── Step 5: Install XFCE4 + X11 inside Ubuntu ───────
step_install_gui() {
    log_step "Installing XFCE4 desktop inside Ubuntu (this takes a while)"

    # Write the inner setup script into rootfs
    cat > "$DIRECTORY/root/setup_gui.sh" <<'INNEREOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "[SETUP] Updating package lists..."
apt-get update -qq

echo "[SETUP] Installing XFCE4 (minimal, lag-free selection)..."
apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    xfce4-taskmanager \
    dbus-x11 \
    x11-xserver-utils \
    xorg \
    xinit \
    mesa-utils \
    libgl1-mesa-dri \
    nano \
    wget \
    curl \
    ca-certificates \
    fonts-noto \
    adwaita-icon-theme-full

# Remove heavy/useless XFCE plugins that cause lag
apt-get remove -y --purge \
    xfce4-screensaver \
    light-locker \
    xscreensaver \
    gnome-screensaver 2>/dev/null || true

apt-get autoremove -y
apt-get clean

echo "[SETUP] Configuring XFCE4 for performance..."

# Disable compositor (biggest source of GPU lag in proot)
mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<'XFWM'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing"    type="bool"   value="false"/>
    <property name="vblank_mode"        type="string" value="off"/>
    <property name="frame_opacity"      type="int"    value="100"/>
    <property name="shadow_opacity"     type="int"    value="0"/>
    <property name="show_dock_shadow"   type="bool"   value="false"/>
    <property name="show_frame_shadow"  type="bool"   value="false"/>
    <property name="show_popup_shadow"  type="bool"   value="false"/>
    <property name="snap_to_border"     type="bool"   value="true"/>
    <property name="snap_to_windows"    type="bool"   value="false"/>
    <property name="wrap_workspaces"    type="bool"   value="false"/>
    <property name="wrap_windows"       type="bool"   value="false"/>
    <property name="double_click_action" type="string" value="maximize"/>
  </property>
</channel>
XFWM

# Disable desktop animations / effects
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<'XFDESK'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="rgba1"       type="array">
            <value type="double" value="0.1"/>
            <value type="double" value="0.1"/>
            <value type="double" value="0.15"/>
            <value type="double" value="1"/>
          </property>
        </property>
      </property>
    </property>
  </property>
</channel>
XFDESK

# Single workspace only (less memory)
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4-workspace.xml <<'WKSP'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="workspace_count" type="int" value="1"/>
  </property>
</channel>
WKSP

echo "[SETUP] GUI setup complete!"
INNEREOF

    chmod +x "$DIRECTORY/root/setup_gui.sh"
    ./startubuntu.sh /root/setup_gui.sh
    log_info "XFCE4 installed inside Ubuntu."
}

# ── Step 6: Create GUI launch script ────────────────
step_create_gui_launcher() {
    log_step "Creating start_gui.sh launcher"

    cat > start_gui.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# ── Kill any leftover X / pulse sessions ──
pkill -f "termux.x11" 2>/dev/null
pkill -f "pulseaudio"  2>/dev/null
sleep 1

# ── Start PulseAudio (audio support) ──
pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1 \
    --daemon 2>/dev/null

# ── Start termux-x11 with performance flags ──
# Resolution tuned for Moto Tab 60 Pro (2560x1600 → render at 1280x800 for smoothness)
termux-x11 :0 \
    -ac \
    -dpi 120 &

sleep 2

# ── Launch XFCE4 inside Ubuntu via proot ──
./startubuntu.sh bash -c "
    # PulseAudio socket for audio
    export PULSE_SERVER=tcp:127.0.0.1:4713

    # X11 display
    export DISPLAY=:0

    # Performance flags for X11 rendering on ARM
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    export LP_NUM_THREADS=4

    # Reduce font rendering overhead
    export FREETYPE_PROPERTIES='truetype:interpreter-version=35'

    # Start dbus if not running
    if [ -z \"\$DBUS_SESSION_BUS_ADDRESS\" ]; then
        eval \$(dbus-launch --sh-syntax)
    fi

    # Start XFCE4
    xfce4-session
" &

sleep 2

# ── Open termux-x11 activity ──
am start \
    --user 0 \
    -n com.termux.x11/com.termux.x11.MainActivity \
    2>/dev/null

echo ""
echo "✅  GUI started! Switch to the termux-x11 window."
echo "    To stop: pkill -f xfce4-session"
EOF

    chmod +x start_gui.sh
    log_info "start_gui.sh created."
}

# ── Step 7: Print final instructions ────────────────
step_print_done() {
    printf "\n"
    printf "${GRN}╔══════════════════════════════════════════════╗${RST}\n"
    printf "${GRN}║   ✅  Installation Complete!                 ║${RST}\n"
    printf "${GRN}╚══════════════════════════════════════════════╝${RST}\n"
    printf "\n"
    printf "${CYN}  HOW TO USE:\n${RST}"
    printf "${CYN}  1. Make sure termux-x11 app is installed on your Tab\n${RST}"
    printf "${CYN}  2. Run:  ${YEL}./start_gui.sh${CYN}  to launch the desktop\n${RST}"
    printf "${CYN}  3. Run:  ${YEL}./startubuntu.sh${CYN}  for terminal-only access\n${RST}"
    printf "\n"
    printf "${CYN}  PERFORMANCE TIPS:\n${RST}"
    printf "${CYN}  • In termux-x11 app → Preferences → set 'Display resolution mode' to 'exact'\n${RST}"
    printf "${CYN}  • Set resolution to 1280x800 for smooth 60fps experience\n${RST}"
    printf "${CYN}  • Enable 'Show additional keyboard' for easy typing\n${RST}"
    printf "${CYN}  • Compositor is disabled by default for maximum smoothness\n${RST}"
    printf "\n"
}

# ── Main ─────────────────────────────────────────────
main() {
    printf "${GRN}"
    printf "  ╔════════════════════════════════════════════╗\n"
    printf "  ║  Ubuntu 22.04 + XFCE4 GUI Installer       ║\n"
    printf "  ║  Optimized for Moto Tab 60 Pro             ║\n"
    printf "  ║  via termux-x11                            ║\n"
    printf "  ╚════════════════════════════════════════════╝\n"
    printf "${RST}\n"

    printf "${YEL}This will install Ubuntu 22.04 + XFCE4 desktop.\n${RST}"
    printf "${YEL}Requires ~2GB storage and a good internet connection.\n\n${RST}"

    if [ "$1" != "-y" ]; then
        printf "${ORG}Continue? [Y/n]: ${RST}"
        read ans
        case "$ans" in
            y|Y|"") ;;
            *)
                log_err "Installation aborted."
                exit 1
                ;;
        esac
    fi

    step_termux_deps
    step_download
    step_configure_rootfs
    step_create_launcher
    step_install_gui
    step_create_gui_launcher
    step_print_done
}

main "$@"

