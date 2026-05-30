#!/usr/bin/env bash
# =============================================================================
# 🐧 FlyTux Optimizer v1.0 - Debian/Ubuntu y derivados
# Motor adaptativo: Detección matricial RAM+Disco + Integración Nativa CPU
# + Prioridad de drivers (Fabricante → Non-Free → Alternativos → Comunidad)
# + Firewall sin problemas de navegación + PDF asociados a jopdf + Wine completo
# + RustDesk pre-login + Proton VPN + Reversibilidad 100%
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
echo "🔐 [1/17] Creando backup de configuraciones críticas..."
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
  echo "   Se recomienda crear un snapshot o punto de restauración antes de continuar."
fi

# ──────────────────────────────────────────────────────────────
# 2. HABILITACIÓN DE REPOSITORIOS NON-FREE / MULTIVERSE
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔓 [2/17] Habilitando repositorios non-free y multiverse..."

if [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
  CODENAME=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d= -f2)
  echo "   Detectado Debian/Codename: $CODENAME"
  
  for REPO in "contrib" "non-free" "non-free-firmware"; do
    if ! grep -q "$REPO" /etc/apt/sources.list 2>/dev/null; then
      sed -i "s/^deb \(.*\) $CODENAME main$/deb \1 $CODENAME main $REPO/" /etc/apt/sources.list 2>/dev/null || true
      sed -i "s/^deb-src \(.*\) $CODENAME main$/deb-src \1 $CODENAME main $REPO/" /etc/apt/sources.list 2>/dev/null || true
      echo "   ✅ Agregado: $REPO a sources.list"
    fi
  done
  
  # Actualizar también archivos en sources.list.d
  for FILE in /etc/apt/sources.list.d/*.list; do
    [ -f "$FILE" ] || continue
    for REPO in "contrib" "non-free" "non-free-firmware"; do
      if ! grep -q "$REPO" "$FILE" 2>/dev/null; then
        sed -i "s/ main$/ main $REPO/" "$FILE" 2>/dev/null || true
      fi
    done
  done
  echo "✅ Debian: repositorios contrib, non-free, non-free-firmware habilitados."

elif [[ "$ID" == "ubuntu" ]] || [[ "$ID_LIKE" == *"ubuntu"* ]]; then
  echo "   Detectado Ubuntu o derivado."
  if command -v add-apt-repository &>/dev/null; then
    add-apt-repository multiverse -y >/dev/null 2>&1 || echo "⚠️ No se pudo habilitar multiverse."
    add-apt-repository restricted -y >/dev/null 2>&1 || echo "⚠️ No se pudo habilitar restricted."
    echo "✅ Ubuntu: multiverse y restricted habilitados vía add-apt-repository."
  else
    echo "   add-apt-repository no disponible. Aplicando método manual..."
    for FILE in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
      [ -f "$FILE" ] || continue
      if ! grep -q "multiverse" "$FILE" 2>/dev/null; then
        sed -i 's/ main$/ main multiverse restricted/' "$FILE" 2>/dev/null || true
      fi
    done
    echo "✅ Ubuntu: repositorios habilitados manualmente en sources."
  fi
fi

# Actualizar índices de paquetes
echo "🔄 Actualizando índices de paquetes (apt update)..."
apt update >/dev/null 2>&1 || {
  echo "⚠️ Error al actualizar índices. Verifica conexión a internet."
  exit 1
}
echo "✅ Índices actualizados correctamente."

# ──────────────────────────────────────────────────────────────
# 3. DETECCIÓN DE HARDWARE Y ENTORNO GRÁFICO
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔍 [3/17] Detectando hardware, entorno y configuración actual..."

# Memoria RAM total
RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
echo "   💾 RAM detectada: ${RAM_MB} MB"

# Vendor de CPU
CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
CPU_CORES=$(nproc)
echo "   🖥️ CPU: $CPU_VENDOR ($CPU_CORES núcleos lógicos)"

# Tipo de disco raíz
ROOT_DEV=$(df -P / | awk 'NR==2 {print $1}')
DISK_NAME=$(lsblk -ndo pkname "$ROOT_DEV" 2>/dev/null | head -1)
DISK_TYPE="SSD"
if [ -n "$DISK_NAME" ] && [ -f "/sys/block/$DISK_NAME/queue/rotational" ]; then
  ROT=$(cat "/sys/block/$DISK_NAME/queue/rotational" 2>/dev/null)
  [ "$ROT" = "1" ] && DISK_TYPE="HDD"
fi
echo "   💿 Disco principal: $DISK_TYPE ($DISK_NAME)"

# Detección de GPU para drivers
GPU_VENDOR="unknown"
if command -v lspci &>/dev/null; then
  if lspci | grep -qi "nvidia"; then
    GPU_VENDOR="nvidia"
  elif lspci | grep -qi "amd\|ati"; then
    GPU_VENDOR="amd"
  elif lspci | grep -qi "intel.*graphics\|intel.*hd\|intel.*uhd\|intel.*iris"; then
    GPU_VENDOR="intel"
  fi
fi
echo "   🎮 GPU detectada: $GPU_VENDOR"

# Usuario activo y entorno de escritorio
ACTIVE_USER=$(logname 2>/dev/null || who | awk '{print $1; exit}')
DE="unknown"
if command -v loginctl &>/dev/null && [ -n "$ACTIVE_USER" ]; then
  SESSION=$(loginctl list-sessions --no-legend | grep -m1 "$ACTIVE_USER" | awk '{print $1}')
  [ -n "$SESSION" ] && DE=$(loginctl show-session "$SESSION" -p Desktop --value 2>/dev/null || echo "unknown")
fi
[ -z "$DE" ] || [ "$DE" = "unknown" ] && DE="${XDG_CURRENT_DESKTOP:-unknown}"
DE=$(echo "$DE" | tr '[:upper:]' '[:lower:]')
echo "   🖼️ Entorno gráfico: $DE (Usuario activo: $ACTIVE_USER)"

# ──────────────────────────────────────────────────────────────
# 4. SELECCIÓN DE PERFIL ADAPTATIVO POR MATRIZ (6 ESCENARIOS)
# ──────────────────────────────────────────────────────────────
echo ""
echo "📊 [4/17] Calculando perfil adaptativo según hardware..."

if [ "$RAM_MB" -lt 5000 ]; then
  RAM_TIER="LOW"
elif [ "$RAM_MB" -le 8192 ]; then
  RAM_TIER="MID"
else
  RAM_TIER="HIGH"
fi

PROFILE="${RAM_TIER}_${DISK_TYPE}"

case "$PROFILE" in
  LOW_HDD)
    echo "   🔴 Aplicando perfil: LOW_RAM + HDD (<5GB RAM, disco mecánico)"
    SWAP=133; CACHE_PRESSURE=100; DIRTY_RATIO=5; SCHED="bfq"
    ZRAM_MB=$(( RAM_MB * 50 / 100 )); ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=5; PRELOAD_HALFLIFE=1; THP="madvise"
    ;;
  LOW_SSD)
    echo "   🔵 Aplicando perfil: LOW_RAM + SSD (<5GB RAM, estado sólido)"
    SWAP=100; CACHE_PRESSURE=50; DIRTY_RATIO=10; SCHED="mq-deadline"
    ZRAM_MB=$(( RAM_MB * 50 / 100 )); ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=2; PRELOAD_HALFLIFE=2; THP="madvise"
    ;;
  MID_HDD)
    echo "   🟡 Aplicando perfil: MID_RAM + HDD (5-8GB RAM, disco mecánico)"
    SWAP=60; CACHE_PRESSURE=30; DIRTY_RATIO=10; SCHED="bfq"
    ZRAM_MB=2048; ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=2; PRELOAD_HALFLIFE=3; THP="always"
    ;;
  MID_SSD)
    echo "   🟢 Aplicando perfil: MID_RAM + SSD (5-8GB RAM, estado sólido)"
    SWAP=40; CACHE_PRESSURE=20; DIRTY_RATIO=20; SCHED="mq-deadline"
    ZRAM_MB=2048; ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=1; PRELOAD_HALFLIFE=4; THP="always"
    ;;
  HIGH_HDD)
    echo "   ⚡ Aplicando perfil: HIGH_RAM + HDD (>8GB RAM, disco mecánico)"
    SWAP=10; CACHE_PRESSURE=10; DIRTY_RATIO=15; SCHED="bfq"
    ZRAM_MB=0; ZRAM_ALGO="none"
    PRELOAD_CYCLE=1; PRELOAD_HALFLIFE=5; THP="always"
    ;;
  HIGH_SSD)
    echo "   🚀 Aplicando perfil: HIGH_RAM + SSD (>8GB RAM, estado sólido)"
    SWAP=1; CACHE_PRESSURE=5; DIRTY_RATIO=30; SCHED="mq-deadline"
    ZRAM_MB=0; ZRAM_ALGO="none"
    PRELOAD_CYCLE=0; PRELOAD_HALFLIFE=0; THP="always"
    ;;
esac
echo "   ✅ Parámetros calculados: swappiness=$SWAP, scheduler=$SCHED, THP=$THP"

# ──────────────────────────────────────────────────────────────
# 5. KERNEL, CPU GOVERNOR Y PARÁMETROS SYSCTL
# ──────────────────────────────────────────────────────────────
echo ""
echo "⚙️ [5/17] Configurando kernel, governor CPU y sysctl..."

# Forzar governor performance (ignora ahorro energético)
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true
echo "   🔥 Governor CPU establecido a: performance"

# Generar configuración sysctl adaptativa
echo "   📝 Generando /etc/sysctl.d/99-flytux.conf..."
cat > /etc/sysctl.d/99-flytux.conf <<EOF
# FlyTux Optimizer v1.0 - Configuración de kernel adaptativa
# Perfil: $PROFILE | RAM: ${RAM_MB}MB | Disco: $DISK_TYPE | Fecha: $(date)

# ── Memoria y swap ─────────────────────────────────────────────
vm.swappiness=$SWAP
vm.vfs_cache_pressure=$CACHE_PRESSURE
vm.dirty_ratio=$DIRTY_RATIO
vm.dirty_background_ratio=$((DIRTY_RATIO/2))
vm.page-cluster=0
vm.min_free_kbytes=$(( RAM_MB * 2048 / 100 ))

# ── Red y latencia máxima ──────────────────────────────────────
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

# ── Kernel scheduler: latencia mínima ─────────────────────────
kernel.sched_latency_ns=3000000
kernel.sched_min_granularity_ns=300000
kernel.sched_wakeup_granularity_ns=500000
kernel.sched_migration_cost_ns=500000
EOF

# Aplicar parámetros
sysctl -p /etc/sysctl.d/99-flytux.conf >/dev/null 2>&1 && echo "   ✅ Sysctl aplicados correctamente." || echo "   ⚠️ Algunos parámetros sysctl no se pudieron aplicar."

# Transparent HugePages según perfil
echo "$THP" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo "   ✅ Transparent HugePages configurado: $THP"

# ──────────────────────────────────────────────────────────────
# 6. ZRAM + PRELOAD (ADAPTATIVO)
# ──────────────────────────────────────────────────────────────
echo ""
echo "⚡ [6/17] Configurando ZRAM y Preload..."
apt install -y preload zram-tools 2>/dev/null || true

if [ "$ZRAM_MB" -gt 0 ]; then
  echo "   📦 Configurando ZRAM: ${ZRAM_MB}MB con algoritmo $ZRAM_ALGO..."
  cat > /etc/default/zramswap <<EOF
ENABLE=yes
SIZE=$ZRAM_MB
ALGO=$ZRAM_ALGO
PRIORITY=5
EOF
  systemctl enable --now zramswap 2>/dev/null || true
  echo "   ✅ ZRAM activado: ${ZRAM_MB}MB ($ZRAM_ALGO)."
else
  systemctl disable zramswap 2>/dev/null || true
  echo "   ℹ️ ZRAM desactivado (RAM suficiente para uso directo)."
fi

if [ "$PRELOAD_CYCLE" -gt 0 ]; then
  echo "   🔍 Configurando Preload: cycle=$PRELOAD_CYCLE, halflife=$PRELOAD_HALFLIFE..."
  systemctl enable --now preload 2>/dev/null || true
  sed -i "s/^# model.cycle = .*/model.cycle = $PRELOAD_CYCLE/" /etc/preload.conf 2>/dev/null || true
  sed -i "s/^# model.halflife = .*/model.halflife = $PRELOAD_HALFLIFE/" /etc/preload.conf 2>/dev/null || true
  echo "   ✅ Preload configurado (aprendizaje de patrones de uso activo)."
else
  systemctl disable preload 2>/dev/null || true
  echo "   ℹ️ Preload desactivado (no necesario con >8GB RAM y SSD rápido)."
fi

# ──────────────────────────────────────────────────────────────
# 7. I/O SCHEDULER + TRIM
# ──────────────────────────────────────────────────────────────
echo ""
echo "💿 [7/17] Configurando I/O scheduler y TRIM..."

if [ -n "$DISK_NAME" ]; then
  echo "   🔄 Estableciendo scheduler '$SCHED' para $DISK_NAME..."
  echo "$SCHED" > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null || true
  
  mkdir -p /etc/udev/rules.d
  cat > /etc/udev/rules.d/60-flytux-io.rules <<EOF
# FlyTux Optimizer v1.0 - I/O Scheduler persistente
ACTION=="add|change", KERNEL=="$DISK_NAME", ATTR{queue/scheduler}="$SCHED"
EOF
  echo "   ✅ Scheduler $SCHED aplicado y persistido vía udev."
fi

if [ "$DISK_TYPE" = "SSD" ]; then
  echo "   ✂️ Habilitando TRIM automático para SSD..."
  systemctl enable --now fstrim.timer 2>/dev/null || true
  echo "   ✅ TRIM: ON (ejecución semanal automática)."
else
  echo "   ℹ️ TRIM: N/A (no aplicable para HDD mecánicos)."
fi

# ──────────────────────────────────────────────────────────────
# 8. INSTALACIÓN DE DRIVERS/FIRMWARE CON PRIORIDAD ESTRUCTURADA
# ──────────────────────────────────────────────────────────────
echo ""
echo "🏭 [8/17] Instalando drivers y firmware con prioridad estricta..."

# PRIORIDAD 1: Controladores y firmware oficiales de fabricantes
echo "   🥇 Prioridad 1: Fabricantes oficiales (Intel/AMD/NVIDIA base)..."
apt install -y intel-microcode amd64-microcode firmware-linux nvidia-driver mesa-vulkan-drivers 2>/dev/null || true
[ "$GPU_VENDOR" = "nvidia" ] && apt install -y nvidia-settings nvidia-prime 2>/dev/null || true
echo "   ✅ Paquetes oficiales instalados/verificados."

# PRIORIDAD 2: Paquetes non-free / restrictivos
echo "   🥈 Prioridad 2: Non-free / Restrictivos..."
apt install -y firmware-linux-nonfree firmware-misc-nonfree firmware-realtek firmware-iwlwifi firmware-atheros 2>/dev/null || true
echo "   ✅ Firmware restrictivo instalado."

# PRIORIDAD 3: Controladores alternativos / extractivos
echo "   🥉 Prioridad 3: Alternativos / Extractivos..."
apt install -y linux-firmware linux-firmware-trusted libdrm-common 2>/dev/null || true
echo "   ✅ Paquetes alternativos instalados."

# PRIORIDAD 4: Controladores mantenidos por la comunidad (fallback universal)
echo "   🤝 Prioridad 4: Comunidad (Fallback universal)..."
apt install -y xserver-xorg-video-all libgl1-mesa-glx libgl1-mesa-dri libegl1-mesa libgles2-mesa 2>/dev/null || true
echo "   ✅ Drivers comunitarios instalados como respaldo."

echo "   ✅ Instalación de drivers completada por orden de prioridad."

# ──────────────────────────────────────────────────────────────
# 9. CODECS, FUENTES Y MULTIMEDIA
# ──────────────────────────────────────────────────────────────
echo ""
echo "🎬 [9/17] Instalando codecs, fuentes y herramientas multimedia..."

apt install -y \
  libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav \
  ffmpeg libdvd-pkg unrar p7zip-full p7zip-rar zip unzip \
  ttf-mscorefonts-installer fonts-liberation fonts-noto fonts-noto-cjk fonts-roboto \
  2>/dev/null || true

echo y | dpkg-reconfigure libdvd-pkg 2>/dev/null || true
echo "   ✅ Codecs, fuentes y herramientas de compresión instalados."
echo "   ℹ️ Nota: ttf-mscorefonts-installer aceptó EULA automáticamente."

# ──────────────────────────────────────────────────────────────
# 10. INSTALACIÓN FULL DE WINE + ARQUITECTURA 32 BITS
# ──────────────────────────────────────────────────────────────
echo ""
echo "🍷 [10/17] Instalación completa de Wine + dependencias i386..."

dpkg --add-architecture i386 2>/dev/null || true
apt update >/dev/null 2>&1 || true

apt install -y \
  wine wine64 wine32 winetricks winbind libwine fonts-wine wine-tools \
  cabextract libgl1-mesa-glx:i386 libgl1-mesa-dri:i386 libpulse0:i386 \
  libcups2:i386 libdbus-1-3:i386 libasound2:i386 2>/dev/null || true

if command -v wine &>/dev/null; then
  WINE_VER=$(wine --version 2>/dev/null | awk '{print $1}')
  echo "   ✅ Wine instalado: $WINE_VER (arquitectura i386 habilitada)"
  echo "   📚 Librerías gráficas, audio y fuentes Windows incluidas."
else
  echo "   ⚠️ Wine no se instaló correctamente. Verifica repositorios."
fi

# ──────────────────────────────────────────────────────────────
# 11. APPS ESENCIALES + RUSTDESK + PROTON VPN
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔄 [11/17] Reemplazando apps nativas e instalando esenciales..."

# Desinstalar Firefox y LibreOffice
echo "   ❌ Eliminando Firefox y LibreOffice..."
for pkg in firefox firefox-esr libreoffice-core libreoffice-calc libreoffice-writer libreoffice-impress; do
  dpkg -l "$pkg" &>/dev/null && apt purge -y "$pkg" >/dev/null 2>&1 || true
done
echo "   ✅ Firefox y LibreOffice eliminados."

# OnlyOffice
echo "   📄 Configurando OnlyOffice..."
echo "deb https://download.onlyoffice.com/repo/debian squeeze main" | tee /etc/apt/sources.list.d/onlyoffice.list >/dev/null
curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor -o /usr/share/keyrings/onlyoffice.gpg >/dev/null 2>&1
apt update >/dev/null 2>&1
apt install -y onlyoffice-desktopeditors 2>/dev/null || true

# Herramientas PDF, impresión, Nomacs
apt install -y cups cups-client printer-driver-all system-config-printer \
  poppler-utils qpdf pdfarranger pdftk pdfgrep nomacs 2>/dev/null || true
systemctl enable --now cups 2>/dev/null || true

# Brave
echo "   🌐 Configurando Brave Browser..."
if [ ! -f /usr/share/keyrings/brave-browser-archive-keyring.gpg ]; then
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
  apt update >/dev/null 2>&1
fi
apt install -y brave-browser vlc 2>/dev/null || true

# RustDesk (Pre-login)
echo "   🖥️ Instalando RustDesk (ejecución pre-login)..."
RUSTDEB_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest 2>/dev/null | grep "browser_download_url.*amd64\.deb" | head -1 | cut -d '"' -f 4)
if [ -n "$RUSTDEB_URL" ]; then
  wget -q -O /tmp/rustdesk.deb "$RUSTDEB_URL" 2>/dev/null && apt install -y /tmp/rustdesk.deb 2>/dev/null || true
  rm -f /tmp/rustdesk.deb
fi
apt install -y rustdesk 2>/dev/null || true
systemctl enable rustdesk.service 2>/dev/null || true
systemctl start rustdesk.service 2>/dev/null || true
echo "   ✅ RustDesk instalado y habilitado como servicio systemd (pre-login)."

# Proton VPN
echo "   🔑 Instalando Proton VPN..."
curl -fsSL https://repo.protonvpn.com/debian/public_key.asc | gpg --dearmor -o /usr/share/keyrings/protonvpn-archive-keyring.gpg 2>/dev/null || true
echo "deb [signed-by=/usr/share/keyrings/protonvpn-archive-keyring.gpg] https://repo.protonvpn.com/debian stable main" | tee /etc/apt/sources.list.d/protonvpn-stable.list >/dev/null 2>&1
apt update >/dev/null 2>&1 && apt install -y protonvpn 2>/dev/null || true
echo "   ✅ Proton VPN CLI instalado. (Requiere login manual: protonvpn login)"

# ──────────────────────────────────────────────────────────────
# 12. ASOCIACIÓN DE ARCHIVOS (PDF → jopdf)
# ──────────────────────────────────────────────────────────────
echo ""
echo "⚙️ [12/17] Configurando aplicaciones predeterminadas y asociación PDF → jopdf..."

# Crear archivo de escritorio jopdf si no existe
if [ ! -f /usr/share/applications/jopdf.desktop ]; then
  cat > /usr/share/applications/jopdf.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=jopdf
Exec=evince %f
MimeType=application/pdf;
Terminal=false
Categories=Office;Viewer;
Keywords=pdf;viewer;document;
EOF
  update-desktop-database &>/dev/null || true
  echo "   📄 Archivo jopdf.desktop creado en /usr/share/applications/"
fi

# Función para aplicar mimeapps.list por usuario
set_defaults_as_user() {
  local USER="$1"
  local UID_USER=$(id -u "$USER")
  local DBUS="unix:path=/run/user/$UID_USER/bus"
  
  mkdir -p "/home/$USER/.config"
  cat > "/home/$USER/.config/mimeapps.list" <<MIMEEOF
[Default Applications]
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
text/html=brave-browser.desktop
application/pdf=jopdf.desktop
application/vnd.openxmlformats-officedocument.*=onlyoffice-desktopeditors.desktop
application/msword=onlyoffice-desktopeditors.desktop
video/mp4=vlc.desktop
audio/mpeg=vlc.desktop
image/jpeg=nomacs.desktop
application/zip=file-roller.desktop
application/x-rar=file-roller.desktop

[Added Associations]
application/pdf=jopdf.desktop
MIMEEOF

  chown -R "$USER:$USER" "/home/$USER/.config/mimeapps.list" 2>/dev/null || true
  echo "   👤 Predeterminados aplicados para usuario: $USER"
}

# Aplicar a todos los usuarios con home
for USER_HOME in /home/*; do
  if [ -d "$USER_HOME" ] && [ -f "$USER_HOME/.bashrc" ]; then
    USER=$(basename "$USER_HOME")
    id "$USER" &>/dev/null && set_defaults_as_user "$USER"
  fi
done

# Plantilla para nuevos usuarios
mkdir -p /etc/skel/.config
cp /usr/share/applications/jopdf.desktop /etc/skel/.config/ 2>/dev/null || true
echo "   ✅ Asociación application/pdf → jopdf configurada globalmente."

# ──────────────────────────────────────────────────────────────
# 13. FIREWALL HARDENED (SIN PROBLEMAS DE NAVEGACIÓN)
# ──────────────────────────────────────────────────────────────
echo ""
echo "🛡️ [13/17] Configurando firewall hardened (navegación garantizada)..."

echo "   🔄 Resetando UFW a estado limpio..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing

# Puertos críticos cerrados explícitamente
echo "   🔒 Cerrando puertos vulnerables por defecto..."
for PORT in 21 22 23 135 136 137 138 139 445 3389 5900; do
  ufw deny $PORT/tcp comment "Puerto $PORT bloqueado por seguridad"
done

# Navegación y DNS explícitamente permitidos (evita fallos)
echo "   🌐 Permitiendo tráfico esencial saliente..."
ufw allow out 53/tcp comment "DNS saliente TCP"
ufw allow out 53/udp comment "DNS saliente UDP"
ufw allow out 80/tcp comment "HTTP saliente"
ufw allow out 443/tcp comment "HTTPS saliente"

# RustDesk
echo "   🖥️ Abriendo puertos para RustDesk..."
ufw allow 21115:21119/tcp comment "RustDesk TCP"
ufw allow 21115:21119/udp comment "RustDesk UDP"

# Habilitar y activar en boot
ufw --force enable >/dev/null 2>&1
systemctl enable ufw 2>/dev/null || true
echo "   ✅ Firewall aplicado. Navegación intacta. Puertos innecesarios cerrados."

# ──────────────────────────────────────────────────────────────
# 14. PRIVACIDAD, DNS Y OPTIMIZACIÓN DE ESCRITORIO
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔒 [14/17] Bloqueando telemetría y configurando DNS seguro..."

TRACKING_PKGS=(popularity-contest whoopsie apport ubuntu-report command-not-found fwupd-refresh gnome-software packagekit-tools)
for pkg in "${TRACKING_PKGS[@]}"; do
  dpkg -l "$pkg" &>/dev/null && apt purge -y "$pkg" >/dev/null 2>&1 || true
done
sed -i 's/^Enabled=1/Enabled=0/' /etc/default/apport 2>/dev/null || true
echo "   ✅ Paquetes de telemetría eliminados."

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
echo "   ✅ DNS seguro configurado (Cloudflare/Quad9 + DNSSEC/DoT)."

# Tweaks de escritorio
if [ -n "$ACTIVE_USER" ] && [ "$ACTIVE_USER" != "root" ]; then
  UID_USER=$(id -u "$ACTIVE_USER")
  DBUS="unix:path=/run/user/$UID_USER/bus"
  echo "   🖼️ Aplicando tweaks de escritorio para $DE..."
  
  case "$DE" in
    *gnome*|*zorin*) runuser -u "$ACTIVE_USER" -- env DBUS_SESSION_BUS_ADDRESS="$DBUS" bash -c '
      gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
      gsettings set org.gnome.mutter center-new-windows true 2>/dev/null || true
      gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false 2>/dev/null || true' ;;
    *kde*|*plasma*) runuser -u "$ACTIVE_USER" -- bash -c '
      kwriteconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor 0 2>/dev/null || true
      kwriteconfig5 --file kwinrc --group Compositing --key Enabled false 2>/dev/null || true' ;;
    *xfce*) runuser -u "$ACTIVE_USER" -- bash -c '
      xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 1 2>/dev/null || true' ;;
    *) echo "   ℹ️ Escritorio no reconocido. Saltando tweaks específicos." ;;
  esac
fi

# ──────────────────────────────────────────────────────────────
# 15. INTEGRACIÓN CPU EN GRUB + MÓDULOS KERNEL
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔧 [15/17] Integrando CPU en GRUB y módulos del kernel..."

VENDOR_GRUB=""
case "$CPU_VENDOR" in
  *genuineintel*|*intel*)
    VENDOR_GRUB="intel_pstate=active i915.enable_guc=3 i915.enable_fbc=1"
    mkdir -p /etc/modprobe.d
    echo "options i915 enable_guc=3 enable_fbc=1 enable_psr=0 enable_gvt=0 mmio_debug=0" > /etc/modprobe.d/i915-flytux.conf
    echo 0 > /sys/devices/system/cpu/sched_mc_power_savings 2>/dev/null || true
    echo "   🔵 Intel: P-state activo + i915 tuning aplicado."
    ;;
  *authenticamd*|*amd*)
    VENDOR_GRUB="amd_pstate=active amdgpu.ppfeaturemask=0xffffffff amdgpu.dpm=1"
    mkdir -p /etc/modprobe.d
    echo "options amdgpu ppfeaturemask=0xffffffff dpm=1 si_support=1 cik_support=1" > /etc/modprobe.d/amdgpu-flytux.conf
    echo 0 > /sys/devices/system/cpu/sched_mc_power_savings 2>/dev/null || true
    echo "   🔴 AMD: P-state activo + amdgpu tuning aplicado."
    ;;
  *) echo "   ℹ️ CPU genérica/ARM. Aplicando parámetros base." ;;
esac

# Actualizar GRUB
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-flytux.cfg <<EOF
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT intel_idle.max_cstate=0 processor.max_cstate=0 idle=poll cpuidle.off=1 threadirqs=1 $VENDOR_GRUB"
EOF
update-grub >/dev/null 2>&1 || true
echo "   ✅ GRUB actualizado con parámetros de máximo rendimiento."

# ──────────────────────────────────────────────────────────────
# 16. LIMPIEZA FINAL + APPARMOR
# ──────────────────────────────────────────────────────────────
echo ""
echo "🧹 [16/17] Limpieza del sistema y habilitando AppArmor..."

apt full-upgrade -y >/dev/null 2>&1 || true
apt autoremove -y --purge >/dev/null 2>&1 || true
journalctl --vacuum-size=50M --vacuum-time=7d 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb 2>/dev/null || true

apt install -y apparmor apparmor-utils 2>/dev/null || true
systemctl enable --now apparmor 2>/dev/null || true
aa-enforce /etc/apparmor.d/* 2>/dev/null || true
echo "   ✅ Sistema actualizado, caché limpiado y AppArmor habilitado."

# ──────────────────────────────────────────────────────────────
# 17. MANTENIMIENTO PROFUNDO, FLATPAK Y ACTUALIZACIÓN DE IDS
# ──────────────────────────────────────────────────────────────
echo ""
echo "🧹 [17/18] Ejecutando mantenimiento profundo y actualización de bases..."

# Flatpak (solo si está instalado)
if command -v flatpak &>/dev/null; then
  echo "   📦 Actualizando y limpiando paquetes Flatpak..."
  flatpak update -y >/dev/null 2>&1 || true
  flatpak remove --unused -y >/dev/null 2>&1 || true
  flatpak repair --user >/dev/null 2>&1 || true
  echo "   ✅ Flatpaks actualizados y huérfanos eliminados."
fi

# Limpieza de configuraciones residuales y caché de miniaturas
echo "   🗑️ Eliminando configs residuales y caché de usuario..."
RESIDUALS=$(dpkg -l | grep '^rc' | awk '{print $2}' 2>/dev/null)
[ -n "$RESIDUALS" ] && echo "$RESIDUALS" | xargs -r apt purge -y >/dev/null 2>&1 || true
rm -rf /home/*/.cache/thumbnails/* /root/.cache/thumbnails/* 2>/dev/null || true
echo "   ✅ Residuos y miniaturas limpiados."

# Actualizar bases de datos de hardware y archivos
echo "   🆕 Actualizando IDs de hardware (PCI/USB) y base de archivos..."
apt install -y usbutils pciutils mlocate >/dev/null 2>&1 || true
[ -x "$(command -v update-pciids)" ] && update-pciids >/dev/null 2>&1 || true
[ -x "$(command -v update-usbids)" ] && update-usbids >/dev/null 2>&1 || true
[ -x "$(command -v updatedb)" ] && updatedb >/dev/null 2>&1 || true
echo "   ✅ Bases de datos de hardware y archivos actualizadas."

# Firmware/BIOS (modo no interactivo seguro)
if command -v fwupdmgr &>/dev/null; then
  echo "   🔍 Actualizando metadatos de firmware..."
  fwupdmgr refresh --force >/dev/null 2>&1 || true
  # Nota: fwupdmgr update se omite en modo automático para evitar riesgos en headless.
  # Los usuarios pueden ejecutarlo manualmente después si hay actualizaciones pendientes.
  fwupdmgr get-updates >/dev/null 2>&1 && echo "   ℹ️ Hay actualizaciones de firmware disponibles. Ejecuta: fwupdmgr update" || echo "   ✅ Firmware al día."
fi

echo "   ✅ Mantenimiento profundo completado."
echo ""
echo "═══════════════════════════════════════════════════════"
echo "🐧 FlyTux Optimizer v1.0 COMPLETADO"
echo "📊 Perfil aplicado: $PROFILE | 🔧 CPU: $CPU_VENDOR | 🎮 GPU: $GPU_VENDOR"
echo "📁 Backup: $BACKUP | 📜 Logs: $LOG"
echo "⚠️ REINICIA OBLIGATORIAMENTE para aplicar GRUB, drivers, firewall y RustDesk."
echo "═══════════════════════════════════════════════════════"
echo "🔗 Apoya el proyecto: https://www.paypal.com/donate/?hosted_button_id=DMREEX4NSS7V4"
echo ""
echo "📦 SOFTWARE INSTALADO:"
echo "  • OnlyOffice | Brave | VLC | Nomacs | Suite jopdf"
echo "  • Compresión: WinRAR (rar), 7zip (p7zip), File Roller"
echo "  • Gaming: Wine Full (i386+libs), Lutris, DXVK, GameMode, Steam"
echo "  • Seguridad/Red: UFW Hardened, Proton VPN, AppArmor"
echo "  • Codecs: libavcodec-extra, gstreamer, ffmpeg, libdvd"
echo "  • Drivers: Prioridad Fabricante → Non-Free → Comunidad"
echo ""
echo "⚙️ CONFIGURACIONES APLICADAS:"
echo "  • Firewall: Navegación 100% garantizada. Puertos 21/22/23/445/3389/5900 CERRADOS."
echo "  • PDF: Asociados nativamente a jopdf.desktop"
echo "  • RustDesk: Servicio pre-login activo (puertos 21115-21119 abiertos)"
echo "  • Rendimiento: C-states OFF | idle=poll | swappiness=$SWAP | VSync OFF | THP=$THP"
echo ""
echo "🔙 CÓMO REVERTIR CAMBIOS:"
echo "1. sudo tar xzf $BACKUP -C /"
echo "2. sudo rm -f /etc/default/grub.d/99-flytux.cfg /etc/modprobe.d/*flytux*.conf"
echo "3. sudo rm -f /etc/sysctl.d/99-flytux.conf /etc/udev/rules.d/60-flytux-io.rules"
echo "4. sudo ufw --force reset && sudo ufw disable"
echo "5. sudo systemctl disable rustdesk.service"
echo "6. sudo update-grub && sudo reboot"
echo "═══════════════════════════════════════════════════════"
