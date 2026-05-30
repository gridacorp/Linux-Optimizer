# 🐧 FlyTux Optimizer v1.0

> **Optimización adaptativa para Debian/Ubuntu** — Detecta tu hardware (RAM + Disco + CPU) y aplica el perfil perfecto para máximo rendimiento. Incluye **gestores de archivos comprimidos** y **aplicaciones predeterminadas configuradas** desde el primer inicio.

![Version](https://img.shields.io/badge/Version-1.0-blue?logo=linux)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Debian%2FUbuntu-orange?logo=debian)
![Features](https://img.shields.io/badge/Features-RAR%20%7C%207zip%20%7C%20Defaults-purple)

<img width="800" alt="FlyTux Banner" src="https://img.shields.io/badge/🐧_FlyTux-Ligero%20%7C%20Rápido%20%7C%20Inteligente-1e90ff?style=for-the-badge" />

---

## ✨ Características Principales

| Feature | Descripción |
|---------|------------|
| 🗜️ **Gestores de compresión** | WinRAR (`rar`), 7zip (`p7zip`), File Roller integrados y configurados |
| ⚙️ **Apps predeterminadas** | Brave, OnlyOffice, VLC, Nomacs y File Roller asignados automáticamente |
| 🔄 **Configuración por usuario** | `mimeapps.list` generado por usuario + `/etc/skel` para nuevos usuarios |
| 🎯 **Soporte multi-DE** | Asociaciones aplicadas vía `xdg-mime`, `gio` (GNOME) y `kwriteconfig5` (KDE) |
| 🔍 **Detección matricial** | 6 perfiles automáticos según RAM (<5GB, 5-8GB, >8GB) + Disco (HDD/SSD) |
| 🔧 **Integración nativa CPU** | Tuning específico para Intel P-State / AMD P-State (estilo macOS) |

---

## 📦 Software Instalado y Configurado como Predeterminado

| Categoría | Aplicación | Tipos de archivo asociados |
|-----------|-----------|---------------------------|
| 🌐 Navegador | **Brave Browser** | `http://`, `https://`, `.html`, `.htm` |
| 📄 Ofimática/PDF | **OnlyOffice** | `.docx`, `.xlsx`, `.pptx`, `.pdf`, `.rtf`, `.txt` |
| 🎬 Multimedia | **VLC** | `.mp4`, `.mkv`, `.webm`, `.mp3`, `.ogg`, `.avi` |
| 🖼️ Imágenes | **Nomacs** | `.jpg`, `.png`, `.gif`, `.webp`, `.bmp`, `.svg` |
| 🗜️ Compresión | **File Roller** (+ RAR/7zip) | `.zip`, `.rar`, `.7z`, `.tar`, `.gz`, `.bz2`, `.xz` |
| 🎮 Gaming | Wine/Lutris/DXVK | `.exe`, `.msi` (vía Wine), juegos de Steam/Lutris |

---

## 🚀 Instalación y Uso

```bash
# 1. Descargar
wget -O flytux-optimizer.sh https://raw.githubusercontent.com/TU_USUARIO/flytux-optimizer/main/flytux-optimizer.sh

# 2. Permisos
chmod +x flytux-optimizer.sh

# 3. Ejecutar (requiere root)
sudo ./flytux-optimizer.sh

# 4. Reiniciar (obligatorio para kernel/GRUB)
sudo reboot
```

### Verificar configuraciones
```bash
xdg-mime query default x-scheme-handler/https   # brave-browser.desktop
xdg-mime query default application/pdf          # onlyoffice-desktopeditors.desktop
xdg-mime query default application/zip          # file-roller.desktop
cat ~/.config/mimeapps.list | head -n 25        # Ver asociaciones completas
```

---

## 🔙 Cómo Revertir Cambios

```bash
sudo tar xzf /tmp/flytux-backup-*.tar.gz -C /
sudo rm -f /etc/default/grub.d/99-flytux.cfg
sudo rm -f /etc/modprobe.d/*flytux*.conf /etc/profile.d/flytux-*.sh
sudo rm -f /etc/sysctl.d/99-flytux.conf /etc/xdg/mimeapps.list
sudo update-grub && sudo reboot
```

---

## ⚠️ Notas Importantes

> [!CAUTION]
> - **C-states OFF + idle=poll**: Mayor consumo energético. Ideal para torres/gaming, no para portátiles en batería.
> - **WinRAR/7zip**: Se instalan desde repositorios oficiales. Para la última versión comercial de WinRAR, visita [rarlab.com](https://www.rarlab.com).
> - **Asociaciones**: Se aplican automáticamente. El backup incluye tu `mimeapps.list` original para revertir si es necesario.

> [!TIP]
> Prueba primero en una máquina virtual con snapshot. Valida que tus apps críticas funcionen antes de aplicar en producción.

---

## 📜 Licencia