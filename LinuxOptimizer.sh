#!/bin/bash

# ------------------------------------------------------------------
# Optimizador Extendido para Debian/Ubuntu y derivados
# (incluye limpieza, seguridad, gaming, redes y swap)
# ------------------------------------------------------------------
# Ejecutar como root: sudo ./optimizar-linux-deb-extendido.sh
# ------------------------------------------------------------------

### 0. Comprobaciones previas ###
if [[ $EUID -ne 0 ]]; then
  echo >&2 "[ERROR] Debes ejecutar este script como root."
  exit 1
fi

# Detectar distro y entorno de escritorio
. /etc/os-release
DISTRO=$ID
DE="${XDG_CURRENT_DESKTOP,,}"

echo "========================================"
echo " Distribución detectada: $PRETTY_NAME"
echo " Entorno de escritorio: $DE"
echo "========================================"
sleep 2

### 1. DESACTIVAR EFECTOS Y ANIMACIONES ###
echo -e "\n[1] Desactivando animaciones y efectos visuales..."
case "$DE" in
  gnome*|zorin*)
    command -v gsettings &>/dev/null && \
      gsettings set org.gnome.desktop.interface enable-animations false
    ;;
  cinnamon)
    gsettings set org.cinnamon.desktop.interface enable-animations false
    ;;
  mate)
    gsettings set org.mate.interface enable-animations false
    ;;
  xfce)
    xfconf-query -c xfwm4 -p /general/use_compositing -s false
    ;;
  *)
    echo "  (Entorno no reconocido, salto animaciones)"
    ;;
esac
sleep 1

### 2. BLOQUEAR TELEMETRÍA ###
echo -e "\n[2] Deshabilitando telemetría (Apport, Whoopsie)..."
systemctl disable apport.service whoopsie.service 2>/dev/null
systemctl stop    apport.service whoopsie.service 2>/dev/null
sleep 1

### 3. ACTUALIZACIONES AUTOMÁTICAS ###
echo -e "\n[3] Deshabilitando unattended-upgrades..."
systemctl disable unattended-upgrades.service 2>/dev/null
systemctl stop    unattended-upgrades.service 2>/dev/null
sleep 1

### 4. OPTIMIZAR ARRANQUE (CPU governor) ###
echo -e "\n[4] Activando CPU governor 'performance'..."
if ! command -v cpupower &>/dev/null; then
  apt update && apt install -y linux-tools-common linux-tools-$(uname -r)
fi
cpupower frequency-set -g performance
sleep 1

### 5. GESTIÓN DE NAVEGADORES (Brave) ###
echo -e "\n[5] Instalando Brave Browser..."
apt install -y curl apt-transport-https
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
     https://brave.com/static-assets/keyrings/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
  > /etc/apt/sources.list.d/brave-browser-release.list
apt update && apt install -y brave-browser
sleep 1

### 6. ELIMINAR CHROME/SNAP/FLATPAK INNECESARIOS ###
echo -e "\n[6] Desinstalando Chromium/Snaps/Flatpaks..."
snap remove chromium --purge 2>/dev/null || true
flatpak uninstall --all --noninteractive 2>/dev/null || true
sleep 1

### 7. DESHABILITAR EXTENSIONES O WIDGETS ###
echo -e "\n[7] Deshabilitando extensiones GNOME/Cinnamon..."
command -v gnome-extensions &>/dev/null && \
  gnome-extensions disable desktop-icons@csoriano 2>/dev/null || true
sleep 1

### 8. TRANSPARENCIA ###
echo -e "\n[8] Forzando tema sin transparencia (si aplica)..."
# Depende del tema GTK; edita tu configuración si es necesario
sleep 1

### 9. APLICACIONES DE INICIO ###
echo -e "\n[9] Limpiando aplicaciones de inicio (autostart)..."
for U in root "$SUDO_USER"; do
  [[ -d /home/$U/.config/autostart ]] && \
    mv /home/$U/.config/autostart/*.desktop /home/$U/.config/autostart.backup/ 2>/dev/null || true
done
sleep 1

### 10. INDEXACIÓN DE BÚSQUEDA (Tracker) ###
echo -e "\n[10] Deshabilitando Tracker..."
systemctl --user mask tracker-miner-fs.service tracker-extract.service 2>/dev/null || true
sleep 1

### 11. OPTIMIZACIÓN DE JOURNALD ###
echo -e "\n[11] Limitando tamaño de logs de systemd-journald..."
sed -i 's|#SystemMaxUse=.*|SystemMaxUse=100M|' /etc/systemd/journald.conf
systemctl restart systemd-journald
sleep 1

### 12. ZRAM (RAM COMPRIMIDA) ###
echo -e "\n[12] Instalando y configurando zram..."
apt update && apt install -y zram-tools
systemctl enable --now zramswap.service 2>/dev/null || true
sleep 1

### 13. ELIMINAR PAQUETES HUÉRFANOS ###
echo -e "\n[13] Eliminando paquetes huérfanos..."
apt autoremove --purge -y
sleep 1

### 14. I/O SCHEDULER (HDD) ###
echo -e "\n[14] Cambiando I/O scheduler a mq-deadline (si HDD)..."
for DISK in /sys/block/sd?; do
  echo mq-deadline > "$DISK/queue/scheduler" 2>/dev/null || true
done
sleep 1

### 15. LIMPIAR CACHÉS Y MINIATURAS ###
echo -e "\n[15] Limpiando caché de APT y miniaturas..."
apt clean
rm -rf /home/*/.cache/thumbnails/* 2>/dev/null || true
sleep 1

### 16. ELIMINAR IDIOMAS NO USADOS ###
echo -e "\n[16] Instalando localepurge para idiomas inutilizados..."
DEBIAN_FRONTEND=noninteractive apt install -y localepurge
sleep 1

### 17. ELIMINAR KERNELS ANTIGUOS ###
echo -e "\n[17] Eliminando kernels antiguos..."
dpkg --list 'linux-image-*' | awk '/^ii/{print $2}' | \
  grep -v "$(uname -r)" | xargs -r apt -y purge
update-grub
sleep 1

### 18. MODO JUEGO (GameMode) ###
echo -e "\n[18] Instalando GameMode..."
apt install -y gamemode
sleep 1

### 19. SEGURIDAD BÁSICA: APPARMOR ###
echo -e "\n[19] Habilitando AppArmor..."
apt install -y apparmor
systemctl enable --now apparmor
sleep 1

### 20. AUDITORÍA (chkrootkit, rkhunter) ###
echo -e "\n[20] Instalando chkrootkit y rkhunter..."
apt install -y chkrootkit rkhunter
chkrootkit
rkhunter --check --sk
sleep 1

### 21. DNS PRIVADOS ###
echo -e "\n[21] Configurando DNS Cloudflare..."
echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1" > /etc/resolv.conf
sleep 1

### 22. DESHABILITAR AVAHI ###
echo -e "\n[22] Deshabilitando avahi-daemon..."
systemctl disable --now avahi-daemon 2>/dev/null || true
sleep 1

### 23. PRELOAD ###
echo -e "\n[23] Instalando preload..."
apt install -y preload
systemctl enable --now preload
sleep 1

### 24. LÍMITE DE TASKS (systemd) ###
echo -e "\n[24] Ajustando DefaultTasksMax..."
grep -q '^DefaultTasksMax=' /etc/systemd/system.conf && \
  sed -i 's/^DefaultTasksMax=.*/DefaultTasksMax=512/' /etc/systemd/system.conf || \
  echo 'DefaultTasksMax=512' >> /etc/systemd/system.conf
sleep 1

### 25. HERRAMIENTAS GAMING ###
echo -e "\n[25] Instalando Wine, Lutris y DXVK..."
apt install -y wine winetricks lutris
# DXVK: se asume apt install de los paquetes disponibles
apt install -y dxvk
sleep 1

### 26. VARIABLES VRAM/VULKAN ###
echo -e "\n[26] Configurando variables de entorno para GPU..."
cat >> /etc/profile.d/gpu_tweaks.sh <<EOF
export __GL_THREADED_OPTIMIZATIONS=1
export MESA_GL_VERSION_OVERRIDE=4.5
EOF
chmod +x /etc/profile.d/gpu_tweaks.sh
sleep 1

### 27. SWAPFILE y SWAPPINESS ###
echo -e "\n[27] Creando swapfile de 4 GB y ajustando swappiness..."
swapoff -a
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl vm.swappiness=10
echo 'vm.swappiness=10' >> /etc/sysctl.conf
sleep 1

### 28. CORTAFUEGOS (UFW) ###
echo -e "\n[28] Instalando y habilitando UFW..."
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
sleep 1

### 29. DESHABILITAR SUSPENSIÓN/HIBERNACIÓN ###
echo -e "\n[29] Enmascarando targets de suspensión e hibernación..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sleep 1

### 30. ELIMINAR BLOATWARE SNAP ###
echo -e "\n[30] Eliminando todos los snaps instalados..."
snap list | awk 'NR>1{print $1}' | xargs -r snap remove --purge
systemctl disable --now snapd 2>/dev/null || true
sleep 1

### 31. ACTUALIZAR SISTEMA ###
echo -e "\n[31] Actualizando todo con APT..."
apt update && apt upgrade -y && apt dist-upgrade -y
sleep 1

### 32. PRIORIZAR PROCESOS CRÍTICOS ###
echo -e "\n[32] Renice para procesos gráficos críticos..."
for P in gnome-shell Xorg cinnamon; do
  pids=$(pgrep -x $P)
  [[ -n $pids ]] && renice -n -5 -p $pids
done
sleep 1

echo -e "\n========================================"
echo " Optimización extendida completada en $PRETTY_NAME."
echo " Por favor, reinicia para aplicar todos los cambios."
echo "========================================"
