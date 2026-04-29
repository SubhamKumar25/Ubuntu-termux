#!/data/data/com.termux/files/usr/bin/bash

set -e

# =========================
# CONFIG
# =========================
UBUNTU_VERSION=22.04
ARCH=arm64
ROOTFS=ubuntu-fs

echo "🔥 Starting Ultimate Ubuntu Setup..."
# =========================
# STEP 1: INSTALL DEPENDENCIES
# =========================
pkg update -y && pkg upgrade -y

pkg install -y \
  proot wget tar git curl \
  x11-repo termux-x11-nightly \
  pulseaudio virglrenderer-android

# =========================
# STEP 2: DOWNLOAD UBUNTU
# =========================
if [ ! -d "$ROOTFS" ]; then
  echo "📥 Downloading Ubuntu..."
  wget https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_VERSION}-base-${ARCH}.tar.gz -O ubuntu.tar.gz
  
  mkdir -p $ROOTFS
  tar -xzf ubuntu.tar.gz -C $ROOTFS
  rm ubuntu.tar.gz
fi

# =========================
# STEP 3: CONFIGURE
# =========================
echo "⚙️ Configuring..."

echo "nameserver 8.8.8.8" > $ROOTFS/etc/resolv.conf

mkdir -p $ROOTFS/etc/apt/apt.conf.d
cat > $ROOTFS/etc/apt/apt.conf.d/99opt <<EOF
Acquire::Languages "none";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

# =========================
# STEP 4: START UBUNTU SCRIPT
# =========================
cat > startubuntu.sh <<'EOF'
#!/bin/bash
unset LD_PRELOAD

proot \
 --link2symlink \
 -0 \
 --kill-on-exit \
 -r ubuntu-fs \
 -b /dev \
 -b /proc \
 -b /sys \
 -b /sdcard \
 -b /storage \
 -b /data/data/com.termux \
 -w /root \
 /usr/bin/env -i \
 HOME=/root \
 PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin \
 TERM=$TERM \
 LANG=C.UTF-8 \
 /bin/bash --login
EOF

chmod +x startubuntu.sh

# =========================
# STEP 5: INSTALL GUI + DEV
# =========================
cat > $ROOTFS/root/setup.sh <<'EOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

apt update -qq

apt install -y --no-install-recommends \
 xfce4 xfce4-terminal dbus-x11 x11-xserver-utils xorg \
 mesa-utils libgl1-mesa-dri nano wget curl git \
 python3 python3-pip nodejs npm \
 fonts-noto chromium

apt remove -y xfce4-screensaver light-locker || true
apt autoremove -y
apt clean

# VS CODE (code-server)
curl -fsSL https://code-server.dev/install.sh | sh

# Jupyter
pip3 install jupyterlab ipykernel

# XFCE performance
mkdir -p ~/.config/xfce4/xfconf/xfce-perchannel-xml
cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<X
<channel name="xfwm4" version="1.0">
 <property name="general">
  <property name="use_compositing" type="bool" value="false"/>
 </property>
</channel>
X

echo "✅ Setup Done"
EOF

chmod +x $ROOTFS/root/setup.sh
./startubuntu.sh /root/setup.sh

# =========================
# STEP 6: GUI LAUNCHER
# =========================
cat > start_gui.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

export PATH=$PREFIX/bin:$PATH

pkill -f termux.x11 2>/dev/null || true
pkill -f pulseaudio 2>/dev/null || true
sleep 1

pulseaudio --start --exit-idle-time=-1 --daemon

$PREFIX/bin/termux-x11 :0 -ac -dpi 120 &
sleep 2

./startubuntu.sh bash -c "

export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export SDL_AUDIODRIVER=pulse

export MESA_GLTHREAD=true
export vblank_mode=0
export LP_NUM_THREADS=\$(nproc)

if [ -e /dev/kgsl-3d0 ]; then
 export GALLIUM_DRIVER=zink
 export LIBGL_ALWAYS_SOFTWARE=0
else
 export GALLIUM_DRIVER=llvmpipe
 export LIBGL_ALWAYS_SOFTWARE=1
fi

if ! pgrep -x dbus-daemon >/dev/null; then
 eval \$(dbus-launch --sh-syntax)
fi

xfce4-session
" &

sleep 2

am start -n com.termux.x11/com.termux.x11.MainActivity

echo "🚀 GUI Started"
EOF

chmod +x start_gui.sh

# =========================
# DONE
# =========================
echo ""
echo "🔥 INSTALL COMPLETE"
echo "Run: ./start_gui.sh"
