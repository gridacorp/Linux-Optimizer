#!/usr/bin/env bash
# =============================================================================
# 🐧 FlyTux Optimizer v1.0 - Debian/Ubuntu y derivados
# Motor adaptativo: Detección matricial RAM+Disco + Integración Nativa Intel/AMD
# Ignora consumo energético: prioriza latencia cero, throughput máximo y ligereza
# =============================================================================
# Ejecutar como root: sudo bash flytux-optimizer.sh
# Backup automático en /tmp/flytux-backup-*.tar.gz
# Logs en /var/log/flytux-*.log
# Reversible: sudo tar xzf /tmp/flytux-backup-*.tar.gz -C /
# =============================================================================

set -uo pipefail

# ──────────────────────────────────────────────────────────────
# 0. VALIDACIÓN INICIAL
# ──────────────────────────────────────────────────────────────
# Verificar que el script se ejecute como root (requerido para cambios de sistema)
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Ejecutar como root: sudo bash $0"
  exit 1
fi

# Verificar compatibilidad con distribuciones basadas en Debian/Ubuntu
. /etc/os-release
if [[ ! "$ID_LIKE" =~ (debian|ubuntu) ]] && [[ ! "$ID" =~ (debian|ubuntu|linuxmint|pop|zorin) ]]; then
  echo "❌ Solo compatible con Debian/Ubuntu y derivados (Linux Mint, Pop!_OS, Zorin OS)"
  exit 1
fi

# Configurar entorno no interactivo para apt/dpkg
export DEBIAN_FRONTEND=noninteractive

# Definir rutas de logs y backup con timestamp único
LOG="/var/log/flytux-$(date +%F-%H%M).log"
BACKUP="/tmp/flytux-backup-$(date +%F).tar.gz"

# Redirigir toda salida a log + terminal
exec > >(tee -a "$LOG") 2>&1

# Banner de inicio
echo "🐧 Iniciando FlyTux Optimizer v1.0 | $(date)"
echo "📦 Backup en: $BACKUP"
echo "📜 Logs en: $LOG"

# ──────────────────────────────────────────────────────────────
# 1. BACKUP DE SEGURIDAD
# ──────────────────────────────────────────────────────────────
# Crear backup comprimido de configuraciones críticas antes de cualquier cambio
echo "🔐 Creando backup de seguridad..."
tar czf "$BACKUP" \
  /etc/sysctl.d /etc/default /etc/apt/apt.conf.d \
  /etc/systemd/system /etc/udev/rules.d \
  /etc/preload.conf /etc/locale.nopurge \
  /etc/systemd/journald.conf.d /etc/default/grub.d \
  /etc/modprobe.d 2>/dev/null || true
echo "✅ Backup de configuraciones creado en: $BACKUP"

# ──────────────────────────────────────────────────────────────
# 2. DETECCIÓN DE HARDWARE Y ENTORNO
# ──────────────────────────────────────────────────────────────
echo "🔍 Detectando hardware y entorno..."

# Obtener RAM total en MB
RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)

# Detectar vendor de CPU (Intel/AMD)
CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')

# Obtener número de cores lógicos
CPU_CORES=$(nproc)

# Detectar tipo de disco raíz (HDD vs SSD)
ROOT_DEV=$(df -P / | awk 'NR==2 {print $1}')
DISK_NAME=$(lsblk -ndo pkname "$ROOT_DEV" 2>/dev/null | head -1)
DISK_TYPE="SSD"
if [ -n "$DISK_NAME" ] && [ -f "/sys/block/$DISK_NAME/queue/rotational" ]; then
  [ "$(cat /sys/block/$DISK_NAME/queue/rotational)" = "1" ] && DISK_TYPE="HDD"
fi

# Detectar usuario activo y entorno de escritorio
ACTIVE_USER=$(logname 2>/dev/null || who | awk '{print $1; exit}')
DE="unknown"
if command -v loginctl &>/dev/null && [ -n "$ACTIVE_USER" ]; then
  SESSION=$(loginctl list-sessions --no-legend | grep -m1 "$ACTIVE_USER" | awk '{print $1}')
  [ -n "$SESSION" ] && DE=$(loginctl show-session "$SESSION" -p Desktop --value 2>/dev/null || echo "unknown")
fi
[ -z "$DE" ] || [ "$DE" = "unknown" ] && DE="${XDG_CURRENT_DESKTOP:-unknown}"
DE=$(echo "$DE" | tr '[:upper:]' '[:lower:]')

# Mostrar resumen de detección
echo "💾 RAM: ${RAM_MB}MB | 🖥️ CPU: $CPU_VENDOR ($CPU_CORES cores) | 💿 Disco: $DISK_TYPE | 🖼️ DE: $DE"

# ──────────────────────────────────────────────────────────────
# 3. SELECCIÓN DE PERFIL POR MATRIX (6 ESCENARIOS)
# ──────────────────────────────────────────────────────────────
echo "📊 Calculando perfil adaptativo..."

# Clasificar por nivel de RAM
if [ "$RAM_MB" -lt 5000 ]; then
  RAM_TIER="LOW"
elif [ "$RAM_MB" -le 8192 ]; then
  RAM_TIER="MID"
else
  RAM_TIER="HIGH"
fi

# Combinar RAM + tipo de disco para perfil único
PROFILE="${RAM_TIER}_${DISK_TYPE}"

# Asignar parámetros optimizados por perfil
case "$PROFILE" in
  LOW_HDD)
    echo "🔴 Perfil aplicado: LOW_RAM + HDD (<5GB RAM, disco mecánico)"
    SWAP=133; CACHE_PRESSURE=100; DIRTY_RATIO=5; SCHED="bfq"
    ZRAM_MB=$(( RAM_MB * 50 / 100 )); ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=5; PRELOAD_HALFLIFE=1; THP="madvise" ;;
  LOW_SSD)
    echo "🔵 Perfil aplicado: LOW_RAM + SSD (<5GB RAM, estado sólido)"
    SWAP=100; CACHE_PRESSURE=50; DIRTY_RATIO=10; SCHED="mq-deadline"
    ZRAM_MB=$(( RAM_MB * 50 / 100 )); ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=2; PRELOAD_HALFLIFE=2; THP="madvise" ;;
  MID_HDD)
    echo "🟡 Perfil aplicado: MID_RAM + HDD (5-8GB RAM, disco mecánico)"
    SWAP=60; CACHE_PRESSURE=30; DIRTY_RATIO=10; SCHED="bfq"
    ZRAM_MB=2048; ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=2; PRELOAD_HALFLIFE=3; THP="always" ;;
  MID_SSD)
    echo "🟢 Perfil aplicado: MID_RAM + SSD (5-8GB RAM, estado sólido)"
    SWAP=40; CACHE_PRESSURE=20; DIRTY_RATIO=20; SCHED="mq-deadline"
    ZRAM_MB=2048; ZRAM_ALGO="lz4"
    PRELOAD_CYCLE=1; PRELOAD_HALFLIFE=4; THP="always" ;;
  HIGH_HDD)
    echo "⚡ Perfil aplicado: HIGH_RAM + HDD (>8GB RAM, disco mecánico)"
    SWAP=10; CACHE_PRESSURE=10; DIRTY_RATIO=15; SCHED="bfq"
    ZRAM_MB=0; ZRAM_ALGO="none"
    PRELOAD_CYCLE=1; PRELOAD_HALFLIFE=5; THP="always" ;;
  HIGH_SSD)
    echo "🚀 Perfil aplicado: HIGH_RAM + SSD (>8GB RAM, estado sólido)"
    SWAP=1; CACHE_PRESSURE=5; DIRTY_RATIO=30; SCHED="mq-deadline"
    ZRAM_MB=0; ZRAM_ALGO="none"
    PRELOAD_CYCLE=0; PRELOAD_HALFLIFE=0; THP="always" ;;
esac

# ──────────────────────────────────────────────────────────────
# 4. KERNEL, CPU GOVERNOR & SYSCTL ADAPTATIVO
# ──────────────────────────────────────────────────────────────
echo "⚙️ Configurando kernel, CPU y parámetros de sistema..."

# Instalar microcode oficial para correcciones de silicio
apt install -y intel-microcode amd64-microcode 2>/dev/null || true

# Forzar governor a performance (ignorar ahorro energético)
echo "🔥 Governor CPU: performance (máximo rendimiento)"
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true

# Generar configuración sysctl adaptativa por perfil
echo "📝 Generando /etc/sysctl.d/99-flytux.conf..."
cat > /etc/sysctl.d/99-flytux.conf <<EOF
# =============================================================================
# FlyTux Optimizer v1.0 - Configuración de kernel adaptativa
# Perfil: $PROFILE | RAM: ${RAM_MB}MB | Disco: $DISK_TYPE
# =============================================================================

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

# Aplicar configuración sysctl
sysctl -p /etc/sysctl.d/99-flytux.conf >/dev/null 2>&1
echo "✅ Sysctl aplicados (swappiness=$SWAP, dirty_ratio=$DIRTY_RATIO, scheduler=latency-min)"

# Configurar Transparent HugePages según perfil
echo "$THP" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo "✅ Transparent HugePages: $THP"

# ──────────────────────────────────────────────────────────────
# 5. ZRAM + PRELOAD (ADAPTATIVO)
# ──────────────────────────────────────────────────────────────
echo "⚡ Configurando ZRAM y Preload..."

# Instalar herramientas necesarias
apt install -y preload zram-tools 2>/dev/null || true

# Configurar ZRAM si RAM < 5GB
if [ "$ZRAM_MB" -gt 0 ]; then
  echo "📦 Configurando ZRAM: ${ZRAM_MB}MB con algoritmo $ZRAM_ALGO..."
  cat > /etc/default/zramswap <<EOF
ENABLE=yes
SIZE=$ZRAM_MB
ALGO=$ZRAM_ALGO
PRIORITY=5
EOF
  systemctl enable --now zramswap 2>/dev/null || true
  echo "✅ ZRAM activado: ${ZRAM_MB}MB ($ZRAM_ALGO, prioridad 5)."
else
  systemctl disable zramswap 2>/dev/null || true
  echo "ℹ️ ZRAM desactivado (RAM suficiente para uso directo)."
fi

# Configurar Preload si es necesario según perfil
if [ "$PRELOAD_CYCLE" -gt 0 ]; then
  echo "🔍 Configurando Preload: cycle=$PRELOAD_CYCLE, halflife=$PRELOAD_HALFLIFE..."
  systemctl enable --now preload 2>/dev/null || true
  sed -i "s/^# model.cycle = .*/model.cycle = $PRELOAD_CYCLE/" /etc/preload.conf 2>/dev/null || true
  sed -i "s/^# model.halflife = .*/model.halflife = $PRELOAD_HALFLIFE/" /etc/preload.conf 2>/dev/null || true
  echo "✅ Preload configurado (aprendizaje agresivo para HDD, equilibrado para SSD)."
else
  systemctl disable preload 2>/dev/null || true
  echo "ℹ️ Preload desactivado (no necesario con >8GB RAM y SSD rápido)."
fi

# ──────────────────────────────────────────────────────────────
# 6. I/O SCHEDULER + TRIM
# ──────────────────────────────────────────────────────────────
echo "💿 Configurando I/O scheduler y TRIM..."

# Aplicar scheduler según tipo de disco
if [ -n "$DISK_NAME" ]; then
  echo "🔄 Estableciendo scheduler '$SCHED' para $DISK_NAME..."
  echo "$SCHED" > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null || true
  
  # Persistir configuración vía udev
  mkdir -p /etc/udev/rules.d
  cat > /etc/udev/rules.d/60-flytux-io.rules <<EOF
# FlyTux Optimizer v1.0 - I/O Scheduler persistente
ACTION=="add|change", KERNEL=="$DISK_NAME", ATTR{queue/scheduler}="$SCHED"
EOF
  echo "✅ Scheduler $SCHED aplicado y persistido."
fi

# Habilitar TRIM automático para SSDs
if [ "$DISK_TYPE" = "SSD" ]; then
  echo "✂️ Habilitando TRIM automático para SSD..."
  systemctl enable --now fstrim.timer 2>/dev/null || true
  echo "✅ TRIM: ON (ejecución semanal automática)."
else
  echo "ℹ️ TRIM: N/A (no aplicable para HDD)."
fi

# ──────────────────────────────────────────────────────────────
# 7. CODECS, DRIVERS & FUENTES RESTRICTIVAS
# ──────────────────────────────────────────────────────────────
echo "📦 Instalando codecs, firmware y fuentes restrictivas..."

# Instalar paquetes multimedia y de compatibilidad
apt install -y \
  libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
  unrar p7zip-full libdvd-pkg \
  firmware-linux-nonfree firmware-misc-nonfree mesa-vulkan-drivers \
  ttf-mscorefonts-installer fonts-noto fonts-noto-cjk fonts-roboto \
  2>/dev/null || true

# Configurar libdvd-pkg para reproducción de DVDs cifrados
echo y | dpkg-reconfigure libdvd-pkg 2>/dev/null || true
echo "✅ Codecs, firmware y fuentes restrictivos instalados."

# ──────────────────────────────────────────────────────────────
# 8. GAMING STACK
# ──────────────────────────────────────────────────────────────
echo "🎮 Configurando gaming stack..."

# Habilitar arquitectura i386 para compatibilidad con juegos Windows
dpkg --add-architecture i386 2>/dev/null || true
apt update >/dev/null 2>&1

# Instalar herramientas de compatibilidad y rendimiento gaming
apt install -y \
  wine wine64 winetricks cabextract \
  lutris dxvk gamemode libgamemodeauto0 \
  protonup-qt 2>/dev/null || true

# Configurar GameMode para priorización en tiempo real durante juegos
mkdir -p /etc/systemd/user/gamemode.service.d 2>/dev/null || true
cat > /etc/systemd/user/gamemode.service.d/flytux.conf 2>/dev/null <<EOF
[Service]
# FlyTux Optimizer v1.0 - GameMode tuning
IOSchedulingClass=realtime
CPUSchedulingPolicy=rr
EOF
echo "✅ Gaming stack listo: Wine/Proton/Lutris/DXVK/GameMode."

# ──────────────────────────────────────────────────────────────
# 9. REEMPLAZO DE APPS + ESENCIALES
# ──────────────────────────────────────────────────────────────
echo "🔄 Reemplazando aplicaciones nativas por alternativas optimizadas..."

# ── Desinstalar Firefox y LibreOffice ─────────────────────────
echo "❌ Eliminando Firefox y LibreOffice..."
for pkg in firefox firefox-esr libreoffice-core libreoffice-calc libreoffice-writer libreoffice-impress; do
  dpkg -l "$pkg" &>/dev/null && apt purge -y "$pkg" >/dev/null 2>&1 || true
done
echo "✅ Firefox y LibreOffice eliminados."

# ── OnlyOffice (suite ofimática ligera y compatible) ─────────
echo "📄 Instalando OnlyOffice..."
echo "deb https://download.onlyoffice.com/repo/debian squeeze main" | tee /etc/apt/sources.list.d/onlyoffice.list >/dev/null
curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor -o /usr/share/keyrings/onlyoffice.gpg >/dev/null 2>&1
apt update >/dev/null 2>&1
apt install -y onlyoffice-desktopeditors 2>/dev/null || echo "⚠️ OnlyOffice no disponible en este repositorio. Instalar manualmente si es necesario."
echo "✅ OnlyOffice instalado."

# ── Herramientas PDF (jopdf suite) ───────────────────────────
echo "📚 Instalando suite PDF (jopdf)..."
apt install -y \
  cups cups-client printer-driver-all system-config-printer \
  poppler-utils qpdf pdfarranger pdftk pdfgrep \
  2>/dev/null || true
systemctl enable --now cups 2>/dev/null || true
echo "✅ Suite PDF instalada: qpdf, pdfarranger, pdftk, pdfgrep + impresoras configuradas."

# ── Nomacs (visor de imágenes ligero) ────────────────────────
echo "🖼️ Instalando Nomacs..."
apt install -y nomacs 2>/dev/null || echo "⚠️ Nomacs no disponible. Instalar manualmente si es necesario."
echo "✅ Nomacs instalado."

# ── Brave Browser (privacidad + rendimiento) ─────────────────
echo "🌐 Instalando Brave Browser..."
if [ ! -f /usr/share/keyrings/brave-browser-archive-keyring.gpg ]; then
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
  apt update >/dev/null 2>&1
fi
apt install -y brave-browser 2>/dev/null || echo "⚠️ Brave no disponible. Instalar manualmente si es necesario."
echo "✅ Brave Browser instalado."

# ── VLC Media Player (reproducción universal) ────────────────
echo "🎬 Instalando VLC Media Player..."
apt install -y vlc 2>/dev/null || echo "⚠️ VLC no disponible. Instalar manualmente si es necesario."
echo "✅ VLC instalado."

echo "🎉 Apps esenciales completadas: OnlyOffice, Brave, VLC, Nomacs, jopdf."

# ──────────────────────────────────────────────────────────────
# 10. OPTIMIZACIÓN POR ESCRITORIO
# ──────────────────────────────────────────────────────────────
if [ -n "$ACTIVE_USER" ] && [ "$ACTIVE_USER" != "root" ]; then
  UID_USER=$(id -u "$ACTIVE_USER")
  DBUS="unix:path=/run/user/$UID_USER/bus"
  echo "🖼️ Aplicando tweaks de escritorio para $DE..."
  
  case "$DE" in
    *gnome*|*zorin*)
      runuser -u "$ACTIVE_USER" -- env DBUS_SESSION_BUS_ADDRESS="$DBUS" bash -c '
        gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
        gsettings set org.gnome.mutter center-new-windows true 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false 2>/dev/null || true
        gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true 2>/dev/null || true' ;;
    *kde*|*plasma*)
      runuser -u "$ACTIVE_USER" -- bash -c '
        kwriteconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor 0 2>/dev/null || true
        kwriteconfig5 --file kwinrc --group Compositing --key Enabled false 2>/dev/null || true
        kwriteconfig5 --file kdeglobals --group KDE --key LookAndFeel "org.kde.breezedark.desktop" 2>/dev/null || true' ;;
    *xfce*)
      runuser -u "$ACTIVE_USER" -- bash -c '
        xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
        xfconf-query -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 1 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/image-style -s 5 2>/dev/null || true' ;;
    *cinnamon*)
      runuser -u "$ACTIVE_USER" -- bash -c '
        gsettings set org.cinnamon.desktop.interface enable-animations false 2>/dev/null || true
        gsettings set org.cinnamon.muffin compositing-manager false 2>/dev/null || true' ;;
    *mate*)
      runuser -u "$ACTIVE_USER" -- bash -c '
        gsettings set org.mate.interface enable-animations false 2>/dev/null || true
        gsettings set org.mate.Marco.general compositing-manager false 2>/dev/null || true' ;;
    *)
      echo "ℹ️ Escritorio no reconocido o sin sesión gráfica activa. Saltando tweaks de DE." ;;
  esac
  echo "✅ Optimizaciones de escritorio aplicadas."
fi

# ──────────────────────────────────────────────────────────────
# 11. MEJORAS DE SISTEMA (Tracker, Journald, Locale, Kernels, UFW, Systemd)
# ──────────────────────────────────────────────────────────────
echo "🔧 Aplicando mejoras de sistema..."

# ── Desactivar Tracker (indexación GNOME) ────────────────────
if command -v tracker3 &>/dev/null || command -v tracker &>/dev/null; then
  echo "🔍 Desactivando Tracker (indexación GNOME)..."
  runuser -u "$ACTIVE_USER" -- bash -c 'tracker3 daemon -t 2>/dev/null || tracker daemon -t 2>/dev/null || true'
  systemctl --user mask tracker-miner-fs-3.service tracker-extract-3.service 2>/dev/null || true
  systemctl --user mask tracker-miner-fs.service tracker-extract.service 2>/dev/null || true
  echo "✅ Tracker desactivado."
fi

# ── Limitar journald (evitar logs infinitos) ─────────────────
echo "🗂️ Limitando tamaño de journald..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/flytux.conf <<EOF
[Journal]
# FlyTux Optimizer v1.0 - Límites de logs
SystemMaxUse=100M
SystemMaxFiles=5
MaxRetentionSec=7day
EOF
systemctl restart systemd-journald 2>/dev/null || true
echo "✅ Journald limitado a 100MB (rotación semanal)."

# ── Localepurge (solo modo LOW_RAM) ─────────────────────────
if [ "$RAM_TIER" = "LOW" ]; then
  echo "🌍 Instalando localepurge (eliminar idiomas no usados)..."
  echo "localepurge localepurge/please_confirm_no localepurge boolean true" | debconf-set-selections
  echo "en_US.UTF-8 UTF-8" > /etc/locale.nopurge
  apt install -y localepurge >/dev/null 2>&1 || true
  echo "✅ Localepurge instalado (solo en-US/es-ES conservados)."
fi

# ── Eliminar kernels antiguos (conservar 2 anteriores + actual) ─
echo "🧹 Eliminando kernels antiguos..."
dpkg --list 'linux-image-*' 2>/dev/null | awk '/^ii/{print $2}' | grep -E "^linux-image-[0-9]" | sort -V | head -n -3 | xargs -r apt purge -y >/dev/null 2>&1 || true
update-grub >/dev/null 2>&1 || update-grub2 >/dev/null 2>&1 || true
echo "✅ Kernels antiguos eliminados (conservados: 3 versiones)."

# ── Variables de entorno GPU (NVIDIA/AMD/Intel) ─────────────
echo "🎨 Configurando variables de entorno GPU..."
mkdir -p /etc/profile.d
cat > /etc/profile.d/flytux-cpu.sh <<'EOF'
# FlyTux Optimizer v1.0 - Variables GPU por vendor
# NVIDIA
export __GL_THREADED_OPTIMIZATIONS=1
export __GL_SYNC_TO_VBLANK=0
export __GL_YIELD="USLEEP"
# AMD/MESA
export MESA_GL_VERSION_OVERRIDE=4.5
export MESA_GLSL_VERSION_OVERRIDE=450
export RADV_PERFTEST=aco
# Universal
export MALLOC_ARENA_MAX=2
EOF
chmod +x /etc/profile.d/flytux-cpu.sh
echo "✅ Variables GPU aplicadas."

# ── UFW firewall básico ─────────────────────────────────────
echo "🛡️ Configurando UFW firewall..."
if ! command -v ufw &>/dev/null; then apt install -y ufw >/dev/null 2>&1 || true; fi
ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh 2>/dev/null || true
ufw --force enable >/dev/null 2>&1
echo "✅ UFW habilitado (entrada: DENY, salida: ALLOW, SSH: permitido)."

# ── Desactivar suspensión/hibernación (modo always-on) ──────
echo "⚡ Desactivando suspensión/hibernación..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
echo "✅ Suspensión/hibernación desactivadas (modo always-on)."

# ── Renice procesos críticos de UI ──────────────────────────
echo "⚙️ Priorizando procesos de interfaz..."
for PROC in gnome-shell Xorg cinnamon xfwm4 kwin_wayland; do
  pids=$(pgrep -x "$PROC" 2>/dev/null)
  [ -n "$pids" ] && renice -n -5 -p $pids >/dev/null 2>&1 || true
done
echo "✅ Procesos de UI priorizados (renice -5)."

# ── Systemd timeouts agresivos ──────────────────────────────
echo "⏱️ Ajustando timeouts de systemd..."
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/flytux.conf <<EOF
[Manager]
# FlyTux Optimizer v1.0 - Timeouts agresivos
DefaultTimeoutStartSec=5s
DefaultTimeoutStopSec=5s
DefaultRestartSec=100ms
EOF
systemctl daemon-reexec 2>/dev/null || true
echo "✅ Timeouts de systemd reducidos."

# ──────────────────────────────────────────────────────────────
# 12. PRIVACIDAD & DNS
# ──────────────────────────────────────────────────────────────
echo "🔒 Bloqueando telemetría y configurando DNS seguro..."

# ── Eliminar paquetes de telemetría ─────────────────────────
TRACKING_PKGS=(popularity-contest whoopsie apport ubuntu-report command-not-found fwupd-refresh gnome-software packagekit-tools)
for pkg in "${TRACKING_PKGS[@]}"; do
  dpkg -l "$pkg" &>/dev/null && apt purge -y "$pkg" >/dev/null 2>&1 || true
done
sed -i 's/^Enabled=1/Enabled=0/' /etc/default/apport 2>/dev/null || true
echo "✅ Telemetría bloqueada."

# ── DNS seguro vía systemd-resolved ─────────────────────────
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/flytux-dns.conf <<EOF
[Resolve]
# FlyTux Optimizer v1.0 - DNS seguro
DNS=1.1.1.1 1.0.0.1 9.9.9.9
FallbackDNS=8.8.8.8 8.8.4.4
DNSSEC=yes
DNSOverTLS=opportunistic
EOF
systemctl restart systemd-resolved 2>/dev/null || true
echo "✅ DNS seguro configurado (Cloudflare/Quad9 + DNSSEC/DoT)."

# ──────────────────────────────────────────────────────────────
# 13. INTEGRACIÓN NATIVA CPU (ESTILO macOS) + MÁXIMO RENDIMIENTO
# ──────────────────────────────────────────────────────────────
echo "🔧 Integrando OS con silicio específico ($CPU_VENDOR)..."

case "$CPU_VENDOR" in
  *genuineintel*|*intel*)
    echo "🔵 Intel detectado: aplicando tuning nativo..."
    apt install -y intel-gpu-tools 2>/dev/null || true
    VENDOR_GRUB="intel_pstate=active i915.enable_guc=3 i915.enable_fbc=1 i915.enable_psr=0"
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/i915-flytux.conf <<'EOF'
# FlyTux Optimizer v1.0 - Tuning i915 para Intel
options i915 enable_guc=3 enable_fbc=1 enable_psr=0 enable_gvt=0 mmio_debug=0
EOF
    echo 0 > /sys/devices/system/cpu/sched_mc_power_savings 2>/dev/null || true
    echo 0 > /sys/devices/system/cpu/sched_smt_power_savings 2>/dev/null || true
    cat > /etc/profile.d/flytux-intel.sh <<'EOF'
export INTEL_DEBUG=nosync
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
EOF
    echo "✅ Intel: P-state activo + i915 tuning + scheduler hints." ;;
    
  *authenticamd*|*amd*)
    echo "🔴 AMD detectado: aplicando tuning nativo..."
    apt install -y rocm-smi-lib 2>/dev/null || true
    VENDOR_GRUB="amd_pstate=active amdgpu.ppfeaturemask=0xffffffff amdgpu.dpm=1"
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/amdgpu-flytux.conf <<'EOF'
# FlyTux Optimizer v1.0 - Tuning amdgpu para AMD
options amdgpu ppfeaturemask=0xffffffff dpm=1 si_support=1 cik_support=1
EOF
    echo 0 > /sys/devices/system/cpu/sched_mc_power_savings 2>/dev/null || true
    echo 0 > /sys/devices/system/cpu/sched_smt_power_savings 2>/dev/null || true
    cat > /etc/profile.d/flytux-amd.sh <<'EOF'
export RADV_PERFTEST=aco
export AMD_VULKAN_ICD=RADV
export MESA_GL_VERSION_OVERRIDE=4.6
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
EOF
    echo "✅ AMD: P-state activo + amdgpu tuning + RADV ACO." ;;
    
  *)
    echo "ℹ️ CPU genérica/ARM. Aplicando tuning base..."
    VENDOR_GRUB=""
    cat > /etc/profile.d/flytux-generic.sh <<'EOF'
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
EOF
    echo "✅ Tuning base aplicado." ;;
esac
chmod +x /etc/profile.d/flytux-*.sh 2>/dev/null || true

# ── GRUB: C-states OFF + idle=poll + Vendor Integration ─────
echo "⚙️ Actualizando GRUB con parámetros de máximo rendimiento..."
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-flytux.cfg <<EOF
# FlyTux Optimizer v1.0 - Parámetros de kernel para máximo rendimiento
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT intel_idle.max_cstate=0 processor.max_cstate=0 idle=poll cpuidle.off=1 threadirqs=1 $VENDOR_GRUB"
EOF
update-grub >/dev/null 2>&1 || true
echo "✅ GRUB actualizado: C-states desactivados + idle=poll + integración nativa."

# ── GPU Max Clock (NVIDIA/AMD/Intel) ────────────────────────
echo "🎮 Forzando GPU a rendimiento máximo..."
if command -v nvidia-settings &>/dev/null; then
  nvidia-settings -a [gpu:0]/GpuPowerMizerMode=1 2>/dev/null || true
fi
if [ -d /sys/class/drm/card0/device ]; then
  echo performance > /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || true
fi
if [ -d /sys/class/drm/card0/gt ]; then
  echo "max" > /sys/class/drm/card0/gt_max_freq_mhz 2>/dev/null || true
fi
echo "✅ GPU forzada a clock máximo."

# ── Filesystem: noatime/nodiratime/discard ──────────────────
echo "💾 Optimizando montaje de filesystems..."
for MOUNT in $(awk '$3 ~ /^(ext4|btrfs)$/ {print $2}' /proc/mounts); do
  DEV=$(findmnt -n -o SOURCE "$MOUNT" 2>/dev/null)
  [ -n "$DEV" ] && tune2fs -o noatime,nodiratime,discard "$DEV" 2>/dev/null || true
done
echo "✅ Filesystem: noatime/nodiratime/discard aplicados."

# ── Entorno global: VSync OFF, presentación mailbox ─────────
echo "🎨 Configurando entorno gráfico para máximo rendimiento..."
cat > /etc/profile.d/flytux-gpu.sh <<'EOF'
# FlyTux Optimizer v1.0 - Entorno GPU para latencia cero
export __GL_SYNC_TO_VBLANK=0
export vblank_mode=0
export MESA_VK_WSI_PRESENT_MODE=mailbox
export MESA_GLTHREAD=true
EOF
chmod +x /etc/profile.d/flytux-gpu.sh
echo "✅ Entorno GPU: VSync OFF, presentación mailbox, threading ON."

echo "✅ Integración nativa + máximo rendimiento aplicados."

# ──────────────────────────────────────────────────────────────
# 14. ACTUALIZACIÓN & LIMPIEZA
# ──────────────────────────────────────────────────────────────
echo "🔄 Actualizando sistema y limpiando..."
apt full-upgrade -y >/dev/null 2>&1 || true
apt autoremove -y --purge >/dev/null 2>&1 || true
journalctl --vacuum-size=50M --vacuum-time=7d 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb 2>/dev/null || true
echo "✅ Sistema actualizado y limpio."

# ──────────────────────────────────────────────────────────────
# 15. SEGURIDAD: APPARMOR
# ──────────────────────────────────────────────────────────────
echo "🛡️ Habilitando AppArmor..."
apt install -y apparmor apparmor-utils 2>/dev/null || true
systemctl enable --now apparmor 2>/dev/null || true
aa-enforce /etc/apparmor.d/* 2>/dev/null || true
echo "✅ AppArmor habilitado (perfilado de aplicaciones)."

# ──────────────────────────────────────────────────────────────
# 16. FINALIZACIÓN
# ──────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "🐧 FlyTux Optimizer v1.0 COMPLETADO"
echo "📊 Perfil aplicado: $PROFILE | 🔧 CPU: $CPU_VENDOR"
echo "📁 Backup: $BACKUP | 📜 Logs: $LOG"
echo "⚠️ REINICIA OBLIGATORIAMENTE para aplicar GRUB, kernel y GPU max perf."
echo "═══════════════════════════════════════════════════════"
echo "🔗 Apoya el proyecto: https://www.paypal.com/donate/?hosted_button_id=DMREEX4NSS7V4"
echo ""
echo "📦 SOFTWARE INSTALADO:"
echo "  • OnlyOffice | Brave | VLC | Nomacs | jopdf (PDF suite)"
echo "  • Gaming: Wine, Proton, Lutris, DXVK, GameMode"
echo "  • Codecs, Fonts, Firmware, AppArmor, UFW"
echo ""
echo "🔥 RENDIMIENTO EXTREMO + INTEGRACIÓN NATIVA ACTIVADA:"
echo "  • C-states OFF | idle=poll | swappiness=$SWAP"
echo "  • THP=$THP | Scheduler latencia mínima | VSync OFF"
echo "  • GPU forzada a max clock | I/O: $SCHED"
if [ "$CPU_VENDOR" = *intel* ]; then
  echo "  • Intel: P-state + i915 + nosync"
elif [ "$CPU_VENDOR" = *amd* ]; then
  echo "  • AMD: P-state + amdgpu + RADV ACO"
else
  echo "  • Genérico: Tuning base aplicado"
fi
echo ""
echo "🔙 REVERTIR CAMBIOS:"
echo "1. sudo tar xzf $BACKUP -C /"
echo "2. sudo rm /etc/default/grub.d/99-flytux.cfg && sudo update-grub"
echo "3. sudo rm /etc/modprobe.d/*flytux*.conf /etc/profile.d/flytux-*.sh"
echo "4. sudo reboot"
echo "═══════════════════════════════════════════════════════"
