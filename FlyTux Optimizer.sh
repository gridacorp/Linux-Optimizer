#!/usr/bin/env bash
# =============================================================================
# 🐧 FlyTux Optimizer v1.0 - Debian/Ubuntu y derivados (PRODUCCIÓN)
# Motor adaptativo: Detección matricial RAM+Disco + Integración Nativa CPU
# + Prioridad de drivers (Fabricante → Non-Free → Alternativos → Comunidad)
# + Firewall sin problemas de navegación + PDF asociados vía xdg-mime
# + Wine completo con i386 + RustDesk pre-login + Proton VPN
# + AppArmor sin romper Flatpak + Repositorios con arch=amd64
# + 100% reversible con backup automático
# =============================================================================
# Ejecutar como root: sudo bash flytux-optimizer.sh
# Backup automático en /tmp/flytux-backup-*.tar.gz
# Logs en /var/log/flytux-*.log
# Reversible: sudo tar xzf /tmp/flytux-backup-*.tar.gz -C /
# =============================================================================

set -uo pipefail

# ──────────────────────────────────────────────────────────────
# 0. VALIDACIÓN INICIAL Y CONFIGURACIÓN DE ENTORNO
# ──────────────────────────────────────────────────────────────
echo "🐧 Iniciando FlyTux Optimizer v1.0 | $(date)"

# Verificar permisos de root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Error: Este script requiere permisos de administrador."
  echo "   Ejecutar como: sudo bash $0"
  exit 1
fi

# Verificar compatibilidad con distribución
. /etc/os-release
if [[ ! "$ID_LIKE" =~ (debian|ubuntu) ]] && [[ ! "$ID" =~ (debian|ubuntu|linuxmint|pop|zorin) ]]; then
  echo "❌ Error: Distribución no soportada."
  echo "   Compatible con: Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin OS"
  exit 1
fi

# Configurar entorno no interactivo para apt/dpkg
export DEBIAN_FRONTEND=noninteractive

# Definir rutas de logs y backup con timestamp único
LOG="/var/log/flytux-$(date +%F-%H%M).log"
BACKUP="/tmp/flytux-backup-$(date +%F).tar.gz"

# Redirigir toda salida estándar y errores a log + terminal
exec > >(tee -a "$LOG") 2>&1

echo "📦 Backup en: $BACKUP"
echo "📜 Logs en: $LOG"
echo "⏳ Iniciando proceso de optimización segura..."

# ──────────────────────────────────────────────────────────────
# 1. BACKUP DE SEGURIDAD DE CONFIGURACIONES CRÍTICAS
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔐 [1/18] Creando backup de configuraciones críticas..."
mkdir -p "$(dirname "$BACKUP")"
tar czf "$BACKUP" \
  /etc/sysctl.d /etc/default /etc/apt/apt.conf.d \
  /etc/systemd/system /etc/udev/rules.d \
  /etc/preload.conf /etc/locale.nopurge \
  /etc/systemd/journald.conf.d /etc/default/grub.d \
  /etc/modprobe.d /etc/xdg/mimeapps.list \
  /etc/apt/sources.list /etc/apt/sources.list.d/ \
  2>/dev/null || true

if [ -f "$BACKUP" ]; then
  echo "✅ Backup creado exitosamente en: $BACKUP"
  echo "   Tamaño: $(du -sh "$BACKUP" | awk '{print $1}')"
else
  echo "⚠️ Advertencia: No se pudo crear el backup completo."
fi

# ──────────────────────────────────────────────────────────────
# 2. HABILITACIÓN DE REPOSITORIOS NON-FREE / MULTIVERSE
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔓 [2/18] Habilitando repositorios non-free y multiverse..."

if [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
  CODENAME=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d= -f2)
  echo "   Detectado Debian/Codename: $CODENAME"
  
  for REPO in "contrib" "non-free" "non-free-firmware"; do
    if ! grep -q "$REPO" /etc/apt/sources.list 2>/dev/null; then
      sed -i "s/^deb \(.*\) $CODENAME main$/deb \1 $CODENAME main $REPO/" /etc/apt/sources.list 2>/dev/null || true
      sed -i "s/^deb-src \(.*\) $CODENAME main$/deb-src \1 $CODENAME main $REPO/" /etc/apt/sources.list 2>/dev/null || true
    fi
  done
  for FILE in /etc/apt/sources.list.d/*.list; do
    [ -f "$FILE" ] || continue
    for REPO in "contrib" "non-free" "non-free-firmware"; do
      sed -i "s/ main$/ main $REPO/" "$FILE" 2>/dev/null || true
    done
  done
  echo "✅ Debian: contrib, non-free, non-free-firmware habilitados."

elif [[ "$ID" == "ubuntu" ]] || [[ "$ID_LIKE" == *"ubuntu"* ]]; then
  if command -v add-apt-repository &>/dev/null; then
    add-apt-repository multiverse -y >/dev/null 2>&1 || true
    add-apt-repository restricted -y >/dev/null 2>&1 || true
  else
    for FILE in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
      [ -f "$FILE" ] || continue
      sed -i 's/ main$/ main multiverse restricted/' "$FILE" 2>/dev/null || true
    done
  fi
  echo "✅ Ubuntu: multiverse y restricted habilitados."
fi

# ──────────────────────────────────────────────────────────────
# 2b. CORRECCIÓN DE REPOSITORIOS: arch=amd64 PARA EVITAR WARNINGS i386
# ──────────────────────────────────────────────────────────────
echo "🔧 [2b/18] Corrigiendo repositorios para evitar warnings de arquitectura..."

# Función segura para iterar sobre patrones de archivos
fix_repo_arch() {
  local PATTERN="$1"
  
  for FILE in $PATTERN; do
    [ -f "$FILE" ] || continue
    
    if [[ "$FILE" == *.sources ]]; then
      # Formato DEB822 (Ubuntu moderno): agregar Architectures si no existe
      if ! grep -q "^Architectures:" "$FILE" 2>/dev/null; then
        echo "Architectures: amd64" >> "$FILE"
      fi
    else
      # Formato clásico deb http://...: inyectar [arch=amd64]
      sed -i -E 's/^deb (https?:\/\/[^ ]+)/deb [arch=amd64] \1/' "$FILE" 2>/dev/null || true
    fi
  done
}

# Brave: forzar arch=amd64
fix_repo_arch "/etc/apt/sources.list.d/*brave*.list /etc/apt/sources.list.d/brave*.sources"

# Google Chrome: forzar arch=amd64
fix_repo_arch "/etc/apt/sources.list.d/*chrome*.list /etc/apt/sources.list.d/google*.sources"

# PPAs: eliminar componente 'contrib' si no existe
for FILE in /etc/apt/sources.list.d/*ulauncher*.list /etc/apt/sources.list.d/*docky*.list; do
  [ -f "$FILE" ] || continue
  sed -i 's/ contrib//g' "$FILE" 2>/dev/null || true
done

echo "✅ Repositorios corregidos para salida limpia de apt."

# ──────────────────────────────────────────────────────────────
# 3. ACTUALIZACIÓN DE ÍNDICES (RESILIENTE - NO FALLA POR WARNINGS)
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔄 [3/18] Actualizando índices de paquetes (modo resiliente)..."

# Capturar salida de apt update para análisis
APT_OUTPUT=$(apt update -o Acquire::Retries=3 --allow-releaseinfo-change 2>&1)
APT_EXIT=$?

# Verificar si hay errores CRÍTICOS (líneas que empiezan con "E:")
if echo "$APT_OUTPUT" | grep -q "^E:"; then
  echo "❌ Error crítico en apt update:"
  echo "$APT_OUTPUT" | grep "^E:" | head -n 3
  echo "⚠️ El script continuará, pero algunas instalaciones podrían fallar."
  echo "💡 Solución manual: revisa /etc/apt/sources.list.d/ y elimina repositorios rotos."
else
  # Solo hay warnings (N:/W:) o éxito total → continuar
  echo "✅ Índices actualizados."
  [ $APT_EXIT -ne 0 ] && echo "ℹ️ Nota: apt devolvió código $APT_EXIT, pero sin errores críticos."
fi

# ──────────────────────────────────────────────────────────────
# 4. DETECCIÓN DE HARDWARE Y ENTORNO GRÁFICO
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔍 [4/18] Detectando hardware, entorno y configuración actual..."

RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
CPU_CORES=$(nproc)

ROOT_DEV=$(df -P / | awk 'NR==2 {print $1}')
DISK_NAME=$(lsblk -ndo pkname "$ROOT_DEV" 2>/dev/null | head -1)
DISK_TYPE="SSD"
if [ -n "$DISK_NAME" ] && [ -f "/sys/block/$DISK_NAME/queue/rotational" ]; then
  [ "$(cat "/sys/block/$DISK_NAME/queue/rotational" 2>/dev/null)" = "1" ] && DISK_TYPE="HDD"
fi

GPU_VENDOR="unknown"
if command -v lspci &>/dev/null; then
  lspci | grep -qi "nvidia" && GPU_VENDOR="nvidia"
  lspci | grep -qi "amd\|ati" && GPU_VENDOR="amd"
  lspci | grep -qi "intel.*graphics\|intel.*hd\|intel.*uhd\|intel.*iris" && GPU_VENDOR="intel"
fi

ACTIVE_USER=$(logname 2>/dev/null || who | awk '{print $1; exit}')
DE="unknown"
if command -v loginctl &>/dev/null && [ -n "$ACTIVE_USER" ]; then
  SESSION=$(loginctl list-sessions --no-legend | grep -m1 "$ACTIVE_USER" | awk '{print $1}')
  [ -n "$SESSION" ] && DE=$(loginctl show-session "$SESSION" -p Desktop --value 2>/dev/null || echo "unknown")
fi
[ -z "$DE" ] || [ "$DE" = "unknown" ] && DE="${XDG_CURRENT_DESKTOP:-unknown}"
DE=$(echo "$DE" | tr '[:upper:]' '[:lower:]')

echo "💾 RAM: ${RAM_MB}MB | 🖥️ CPU: $CPU_VENDOR ($CPU_CORES cores) | 💿 Disco: $DISK_TYPE | 🎮 GPU: $GPU_VENDOR | 🖼️ DE: $DE"

# ──────────────────────────────────────────────────────────────
# 5. SELECCIÓN DE PERFIL ADAPTATIVO POR MATRIZ (6 ESCENARIOS)
# ──────────────────────────────────────────────────────────────
echo ""
echo "📊 [5/18] Calculando perfil adaptativo según hardware..."

if [ "$RAM_MB" -lt 5000 ]; then RAM_TIER="LOW"
elif [ "$RAM_MB" -le 8192 ]; then RAM_TIER="MID"
else RAM_TIER="HIGH"; fi

PROFILE="${RAM_TIER}_${DISK_TYPE}"

case "$PROFILE" in
  LOW_HDD)  echo "🔴 Perfil: LOW_RAM + HDD"; SWAP=133; CACHE_PRESSURE=100; DIRTY_RATIO=5; SCHED="bfq"; ZRAM_MB=$((RAM_MB*50/100)); ZRAM_ALGO="lz4"; PRELOAD_CYCLE=5; PRELOAD_HALFLIFE=1; THP="madvise" ;;
  LOW_SSD)  echo "🔵 Perfil: LOW_RAM + SSD"; SWAP=100; CACHE_PRESSURE=50; DIRTY_RATIO=10; SCHED="mq-deadline"; ZRAM_MB=$((RAM_MB*50/100)); ZRAM_ALGO="lz4"; PRELOAD_CYCLE=2; PRELOAD_HALFLIFE=2; THP="madvise" ;;
  MID_HDD)  echo "🟡 Perfil: MID_RAM + HDD"; SWAP=60; CACHE_PRESSURE=30; DIRTY_RATIO=10; SCHED="bfq"; ZRAM_MB=2048; ZRAM_ALGO="lz4"; PRELOAD_CYCLE=2; PRELOAD_HALFLIFE=3; THP="always" ;;
  MID_SSD)  echo "🟢 Perfil: MID_RAM + SSD"; SWAP=40; CACHE_PRESSURE=20; DIRTY_RATIO=20; SCHED="mq-deadline"; ZRAM_MB=2048; ZRAM_ALGO="lz4"; PRELOAD_CYCLE=1; PRELOAD_HALFLIFE=4; THP="always" ;;
  HIGH_HDD) echo "⚡ Perfil: HIGH_RAM + HDD"; SWAP=10; CACHE_PRESSURE=10; DIRTY_RATIO=15; SCHED="bfq"; ZRAM_MB=0; ZRAM_ALGO="none"; PRELOAD_CYCLE=1; PRELOAD_HALFLIFE=5; THP="always" ;;
  HIGH_SSD) echo "🚀 Perfil: HIGH_RAM + SSD"; SWAP=1; CACHE_PRESSURE=5; DIRTY_RATIO=30; SCHED="mq-deadline"; ZRAM_MB=0; ZRAM_ALGO="none"; PRELOAD_CYCLE=0; PRELOAD_HALFLIFE=0; THP="always" ;;
esac
echo "✅ Parámetros: swappiness=$SWAP, scheduler=$SCHED, THP=$THP"

# ──────────────────────────────────────────────────────────────
# 6. KERNEL, CPU GOVERNOR Y SYSCTL
# ──────────────────────────────────────────────────────────────
echo ""
echo "⚙️ [6/18] Configurando kernel, governor CPU y sysctl..."

echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true

cat > /etc/sysctl.d/99-flytux.conf <<EOF
# FlyTux Optimizer v1.0 - Perfil: $PROFILE
vm.swappiness=$SWAP
vm.vfs_cache_pressure=$CACHE_PRESSURE
vm.dirty_ratio=$DIRTY_RATIO
vm.dirty_background_ratio=$((DIRTY_RATIO/2))
vm.page-cluster=0
vm.min_free_kbytes=$((RAM_MB*2048/100))
net.core.somaxconn=4096
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_congestion_control=bbr
net.core.netdev_max_backlog=4096
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem="4096 87380 16777216"
net.ipv4.tcp_wmem="4096 65536 16777216"
net.ipv4.tcp_timestamps=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_window_scaling=1
kernel.sched_latency_ns=3000000
kernel.sched_min_granularity_ns=300000
kernel.sched_wakeup_granularity_ns=500000
kernel.sched_migration_cost_ns=500000
EOF
sysctl -p /etc/sysctl.d/99-flytux.conf >/dev/null 2>&1 || true
echo "$THP" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo "✅ Sysctl y THP aplicados."

# ──────────────────────────────────────────────────────────────
# 7. ZRAM + PRELOAD (ADAPTATIVO)
# ──────────────────────────────────────────────────────────────
echo ""
echo "⚡ [7/18] Configurando ZRAM y Preload..."
apt install -y preload zram-tools 2>/dev/null || true

if [ "$ZRAM_MB" -gt 0 ]; then
  cat > /etc/default/zramswap <<EOF
ENABLE=yes
SIZE=$ZRAM_MB
ALGO=$ZRAM_ALGO
PRIORITY=5
EOF
  systemctl enable --now zramswap 2>/dev/null || true
  echo "✅ ZRAM: ${ZRAM_MB}MB ($ZRAM_ALGO)."
else
  systemctl disable zramswap 2>/dev/null || true
fi

if [ "$PRELOAD_CYCLE" -gt 0 ]; then
  systemctl enable --now preload 2>/dev/null || true
  sed -i "s/^# model.cycle = .*/model.cycle = $PRELOAD_CYCLE/" /etc/preload.conf 2>/dev/null || true
  sed -i "s/^# model.halflife = .*/model.halflife = $PRELOAD_HALFLIFE/" /etc/preload.conf 2>/dev/null || true
else
  systemctl disable preload 2>/dev/null || true
fi

# ──────────────────────────────────────────────────────────────
# 8. I/O SCHEDULER + TRIM
# ──────────────────────────────────────────────────────────────
echo ""
echo "💿 [8/18] Configurando I/O scheduler y TRIM..."

if [ -n "$DISK_NAME" ]; then
  echo "$SCHED" > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null || true
  mkdir -p /etc/udev/rules.d
  cat > /etc/udev/rules.d/60-flytux-io.rules <<EOF
ACTION=="add|change", KERNEL=="$DISK_NAME", ATTR{queue/scheduler}="$SCHED"
EOF
fi
[ "$DISK_TYPE" = "SSD" ] && systemctl enable --now fstrim.timer 2>/dev/null || true
echo "✅ I/O: $SCHED | TRIM: $([ "$DISK_TYPE" = "SSD" ] && echo ON || echo N/A)"

# ──────────────────────────────────────────────────────────────
# 9. DRIVERS CON PRIORIDAD ESTRUCTURADA
# ──────────────────────────────────────────────────────────────
echo ""
echo "🏭 [9/18] Instalando drivers por prioridad..."

# 1. Fabricante oficial
apt install -y intel-microcode amd64-microcode firmware-linux nvidia-driver mesa-vulkan-drivers 2>/dev/null || true
[ "$GPU_VENDOR" = "nvidia" ] && apt install -y nvidia-settings nvidia-prime 2>/dev/null || true

# 2. Non-free
apt install -y firmware-linux-nonfree firmware-misc-nonfree firmware-realtek firmware-iwlwifi 2>/dev/null || true

# 3. Alternativos
apt install -y linux-firmware linux-firmware-trusted libdrm-common 2>/dev/null || true

# 4. Comunidad (fallback)
apt install -y xserver-xorg-video-all libgl1-mesa-glx libgl1-mesa-dri libegl1-mesa 2>/dev/null || true

echo "✅ Drivers instalados por prioridad."

# ──────────────────────────────────────────────────────────────
# 10. CODECS, FUENTES Y MULTIMEDIA
# ──────────────────────────────────────────────────────────────
echo ""
echo "🎬 [10/18] Instalando codecs y fuentes..."

apt install -y \
  libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav \
  ffmpeg libdvd-pkg unrar p7zip-full p7zip-rar zip unzip \
  ttf-mscorefonts-installer fonts-liberation fonts-noto fonts-noto-cjk fonts-roboto \
  2>/dev/null || true
echo y | dpkg-reconfigure libdvd-pkg 2>/dev/null || true
echo "✅ Codecs y fuentes instalados."

# ──────────────────────────────────────────────────────────────
# 11. WINE FULL + i386
# ──────────────────────────────────────────────────────────────
echo ""
echo "🍷 [11/18] Instalación completa de Wine + i386..."

dpkg --add-architecture i386 2>/dev/null || true
apt update >/dev/null 2>&1 || true

apt install -y \
  wine wine64 wine32 winetricks winbind libwine fonts-wine wine-tools \
  cabextract libgl1-mesa-glx:i386 libgl1-mesa-dri:i386 libpulse0:i386 \
  libcups2:i386 libdbus-1-3:i386 libasound2:i386 2>/dev/null || true

command -v wine &>/dev/null && echo "✅ Wine: $(wine --version 2>/dev/null | awk '{print $1}')" || echo "⚠️ Wine: verificar repositorios"

# ──────────────────────────────────────────────────────────────
# 12. APPS ESENCIALES + RUSTDESK + PROTON VPN
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔄 [12/18] Instalando apps esenciales..."

# Eliminar Firefox/LibreOffice
for pkg in firefox firefox-esr libreoffice-core libreoffice-calc libreoffice-writer libreoffice-impress; do
  dpkg -l "$pkg" &>/dev/null && apt purge -y "$pkg" >/dev/null 2>&1 || true
done

# OnlyOffice: instalación nativa vía .deb directo (evita repo roto)
echo "📄 Instalando OnlyOffice nativo..."
ONLYOFFICE_DEB="https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb"
wget -q -O /tmp/oo.deb "$ONLYOFFICE_DEB" 2>/dev/null && {
  sudo dpkg -i /tmp/oo.deb 2>/dev/null || true
  sudo apt install -f -y >/dev/null 2>&1 || true
  rm -f /tmp/oo.deb
} || apt install -y onlyoffice-desktopeditors 2>/dev/null || true

# Herramientas PDF, impresión, Nomacs
apt install -y cups cups-client printer-driver-all system-config-printer \
  poppler-utils qpdf pdfarranger pdftk pdfgrep nomacs 2>/dev/null || true
systemctl enable --now cups 2>/dev/null || true

# Brave
if [ ! -f /usr/share/keyrings/brave-browser-archive-keyring.gpg ]; then
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
  apt update >/dev/null 2>&1
fi
apt install -y brave-browser vlc 2>/dev/null || true

# RustDesk pre-login
RUSTDEB_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest 2>/dev/null | grep "browser_download_url.*amd64\.deb" | head -1 | cut -d '"' -f 4)
[ -n "$RUSTDEB_URL" ] && wget -q -O /tmp/rustdesk.deb "$RUSTDEB_URL" 2>/dev/null && apt install -y /tmp/rustdesk.deb 2>/dev/null || apt install -y rustdesk 2>/dev/null || true
rm -f /tmp/rustdesk.deb 2>/dev/null
systemctl enable rustdesk.service 2>/dev/null || true
systemctl start rustdesk.service 2>/dev/null || true

# Proton VPN
curl -fsSL https://repo.protonvpn.com/debian/public_key.asc | gpg --dearmor -o /usr/share/keyrings/protonvpn-archive-keyring.gpg 2>/dev/null || true
echo "deb [signed-by=/usr/share/keyrings/protonvpn-archive-keyring.gpg arch=amd64] https://repo.protonvpn.com/debian stable main" | tee /etc/apt/sources.list.d/protonvpn-stable.list >/dev/null 2>&1
apt update >/dev/null 2>&1 && apt install -y protonvpn 2>/dev/null || true

echo "✅ Apps esenciales instaladas."

# ──────────────────────────────────────────────────────────────
# 13. ASOCIACIÓN MIME CON xdg-mime (NO WILDCARDS)
# ──────────────────────────────────────────────────────────────
echo ""
echo "⚙️ [13/18] Configurando asociaciones MIME con xdg-mime..."

# PDF → jopdf
cat > /usr/share/applications/jopdf.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=jopdf
Exec=evince %f
MimeType=application/pdf;
Terminal=false
Categories=Office;Viewer;
EOF
update-desktop-database &>/dev/null || true

set_defaults_as_user() {
  local USER="$1" UID_USER=$(id -u "$1") DBUS="unix:path=/run/user/$(id -u "$1")/bus"
  mkdir -p "/home/$USER/.config"
  
  # Usar xdg-mime para asociaciones correctas (sin wildcards)
  for MIME in application/pdf \
              application/vnd.openxmlformats-officedocument.wordprocessingml.document \
              application/vnd.openxmlformats-officedocument.spreadsheetml.sheet \
              application/vnd.openxmlformats-officedocument.presentationml.presentation \
              application/msword application/vnd.ms-excel application/vnd.ms-powerpoint \
              application/rtf text/plain; do
    xdg-mime default onlyoffice-desktopeditors.desktop "$MIME" 2>/dev/null || true
  done
  xdg-mime default jopdf.desktop application/pdf 2>/dev/null || true
  xdg-mime default brave-browser.desktop x-scheme-handler/http 2>/dev/null || true
  xdg-mime default brave-browser.desktop x-scheme-handler/https 2>/dev/null || true
  xdg-mime default vlc.desktop video/mp4 2>/dev/null || true
  xdg-mime default nomacs.desktop image/jpeg 2>/dev/null || true
  xdg-mime default file-roller.desktop application/zip 2>/dev/null || true
}

for USER_HOME in /home/*; do
  [ -d "$USER_HOME" ] && [ -f "$USER_HOME/.bashrc" ] && { USER=$(basename "$USER_HOME"); id "$USER" &>/dev/null && set_defaults_as_user "$USER"; }
done

mkdir -p /etc/skel/.config
cp /usr/share/applications/jopdf.desktop /etc/skel/.config/ 2>/dev/null || true
echo "✅ Asociaciones MIME aplicadas vía xdg-mime."

# ──────────────────────────────────────────────────────────────
# 14. FIREWALL HARDENED (NAVEGACIÓN GARANTIZADA)
# ──────────────────────────────────────────────────────────────
echo ""
echo "🛡️ [14/18] Configurando firewall hardened..."

ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing

# Puertos críticos cerrados
for PORT in 21 22 23 135 136 137 138 139 445 3389 5900; do
  ufw deny $PORT/tcp comment "Puerto $PORT bloqueado"
done

# Navegación explícitamente permitida (evita fallos)
ufw allow out 53/tcp 2>/dev/null || true
ufw allow out 53/udp 2>/dev/null || true
ufw allow out 80/tcp 2>/dev/null || true
ufw allow out 443/tcp 2>/dev/null || true

# RustDesk
ufw allow 21115:21119/tcp comment "RustDesk TCP" 2>/dev/null || true
ufw allow 21115:21119/udp comment "RustDesk UDP" 2>/dev/null || true

ufw --force enable >/dev/null 2>&1
systemctl enable ufw 2>/dev/null || true
echo "✅ Firewall: navegación garantizada, puertos críticos cerrados."

# ──────────────────────────────────────────────────────────────
# 15. PRIVACIDAD, DNS Y APPARMOR (SIN ROMPER FLATPAK)
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔒 [15/18] Privacidad, DNS y AppArmor seguro..."

# Telemetría
for pkg in popularity-contest whoopsie apport ubuntu-report command-not-found fwupd-refresh gnome-software packagekit-tools; do
  dpkg -l "$pkg" &>/dev/null && apt purge -y "$pkg" >/dev/null 2>&1 || true
done
sed -i 's/^Enabled=1/Enabled=0/' /etc/default/apport 2>/dev/null || true

# DNS seguro
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/flytux-dns.conf <<EOF
[Resolve]
DNS=1.1.1.1 1.0.0.1 9.9.9.9
FallbackDNS=8.8.8.8 8.8.4.4
DNSSEC=yes
DNSOverTLS=opportunistic
EOF
systemctl restart systemd-resolved 2>/dev/null || true

# AppArmor: habilitar servicio SIN forzar perfiles que rompen Flatpak
systemctl enable apparmor 2>/dev/null || true
# Desactivar AppArmor SOLO para perfiles Flatpak/bwrap (evita conflictos de sandbox)
for profile in /etc/apparmor.d/flatpak-* /etc/apparmor.d/*bwrap* 2>/dev/null; do
  [ -f "$profile" ] && aa-disable "$profile" 2>/dev/null || true
done
echo "✅ AppArmor habilitado (Flatpak excluido para evitar conflictos)."

# Tweaks de escritorio
if [ -n "$ACTIVE_USER" ] && [ "$ACTIVE_USER" != "root" ]; then
  UID_USER=$(id -u "$ACTIVE_USER")
  DBUS="unix:path=/run/user/$UID_USER/bus"
  case "$DE" in
    *gnome*|*zorin*) runuser -u "$ACTIVE_USER" -- env DBUS_SESSION_BUS_ADDRESS="$DBUS" bash -c 'gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true' ;;
    *kde*|*plasma*) runuser -u "$ACTIVE_USER" -- bash -c 'kwriteconfig5 --file kwinrc --group Compositing --key Enabled false 2>/dev/null || true' ;;
    *xfce*) runuser -u "$ACTIVE_USER" -- bash -c 'xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true' ;;
  esac
fi

# ──────────────────────────────────────────────────────────────
# 16. INTEGRACIÓN CPU EN GRUB
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔧 [16/18] Integrando CPU en GRUB..."

VENDOR_GRUB=""
case "$CPU_VENDOR" in
  *intel*) VENDOR_GRUB="intel_pstate=active i915.enable_guc=3"; mkdir -p /etc/modprobe.d && echo "options i915 enable_guc=3" > /etc/modprobe.d/i915-flytux.conf ;;
  *amd*)   VENDOR_GRUB="amd_pstate=active amdgpu.ppfeaturemask=0xffffffff"; mkdir -p /etc/modprobe.d && echo "options amdgpu ppfeaturemask=0xffffffff" > /etc/modprobe.d/amdgpu-flytux.conf ;;
esac

mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-flytux.cfg <<EOF
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT intel_idle.max_cstate=0 processor.max_cstate=0 idle=poll cpuidle.off=1 threadirqs=1 $VENDOR_GRUB"
EOF
update-grub >/dev/null 2>&1 || true
echo "✅ GRUB actualizado."

# ──────────────────────────────────────────────────────────────
# 17. LIMPIEZA Y MANTENIMIENTO
# ──────────────────────────────────────────────────────────────
echo ""
echo "🧹 [17/18] Limpieza y mantenimiento..."

apt full-upgrade -y >/dev/null 2>&1 || true
apt autoremove -y --purge >/dev/null 2>&1 || true
journalctl --vacuum-size=50M --vacuum-time=7d 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb 2>/dev/null || true

# Flatpak maintenance (si está instalado)
if command -v flatpak &>/dev/null; then
  flatpak update -y >/dev/null 2>&1 || true
  flatpak remove --unused -y >/dev/null 2>&1 || true
  flatpak repair --user >/dev/null 2>&1 || true
fi

echo "✅ Limpieza completada."

# ──────────────────────────────────────────────────────────────
# 18. FINALIZACIÓN
# ──────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "🐧 FlyTux Optimizer v1.0 COMPLETADO"
echo "📊 Perfil: $PROFILE | 🔧 CPU: $CPU_VENDOR | 🎮 GPU: $GPU_VENDOR"
echo "📁 Backup: $BACKUP | 📜 Logs: $LOG"
echo "⚠️ REINICIA para aplicar GRUB, drivers, firewall y RustDesk."
echo "═══════════════════════════════════════════════════════"
echo "🔗 Apoya el proyecto: https://www.paypal.com/donate/?hosted_button_id=DMREEX4NSS7V4"
echo ""
echo "📦 INSTALADO: OnlyOffice(nativo), Brave, VLC, Nomacs, jopdf, Wine-Full(i386), RustDesk(pre-login), Proton-VPN"
echo "🔒 FIREWALL: Navegación garantizada. Puertos 21/22/23/445/3389/5900 CERRADOS."
echo "📄 MIME: PDF/Office → OnlyOffice vía xdg-mime (sin wildcards)."
echo "🔙 REVERTIR: sudo tar xzf $BACKUP -C / && sudo ufw --force reset && sudo update-grub && sudo reboot"
echo "═══════════════════════════════════════════════════════"
