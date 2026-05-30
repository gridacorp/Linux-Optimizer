# 🐧 FlyTux Optimizer v1.0 - Script de Instalación Actualizado

## 🚀 Instalación Rápida (Nuevo Repositorio)

```bash
# 1. Clonar el repositorio oficial
git clone https://github.com/gridacorp/Flytux-Linux-Optimizer.git

# 2. Entrar al directorio
cd Flytux-Linux-Optimizer

# 3. Dar permisos de ejecución
chmod +x "FlyTux Optimizer.sh"

# 4. Ejecutar como root
sudo "./FlyTux Optimizer.sh"

# 5. Reiniciar para aplicar cambios de kernel/GRUB
sudo reboot
```

---

## 📋 Instalación Paso a Paso con Verificación

```bash
# ── Paso 1: Clonar repositorio ───────────────────────────────
git clone https://github.com/gridacorp/Flytux-Linux-Optimizer.git
cd Flytux-Linux-Optimizer

# ── Paso 2: Verificar integridad del script (opcional pero recomendado) ──
# Verificar que el script existe y tiene tamaño razonable
ls -lh "FlyTux Optimizer.sh"
# Debería mostrar ~30-50KB

# Verificar sintaxis bash sin ejecutar
bash -n "FlyTux Optimizer.sh" && echo "✅ Sintaxis válida" || echo "❌ Error de sintaxis"

# ── Paso 3: Ejecutar ─────────────────────────────────────────
chmod +x "FlyTux Optimizer.sh"
sudo "./FlyTux Optimizer.sh"

# ── Paso 4: Reiniciar ────────────────────────────────────────
sudo reboot
```

---

## 🔍 Verificación Post-Instalación

```bash
# Verificar que el script se ejecutó correctamente
grep "COMPLETADO" /var/log/flytux-*.log | tail -n 1

# Verificar perfil aplicado
grep "Perfil:" /var/log/flytux-*.log | tail -n 1

# Verificar firewall
sudo ufw status verbose

# Verificar asociaciones MIME
xdg-mime query default application/pdf
xdg-mime query default application/vnd.openxmlformats-officedocument.wordprocessingml.document

# Verificar servicios críticos
systemctl is-enabled rustdesk.service
protonvpn status 2>/dev/null || echo "ℹ️ ProtonVPN: requiere login manual"
wine --version 2>/dev/null || echo "ℹ️ Wine: verificar instalación"
```

---

## 🔙 Cómo Revertir Cambios

```bash
# 1. Restaurar backup automático
sudo tar xzf /tmp/flytux-backup-*.tar.gz -C /

# 2. Limpiar configuraciones específicas de FlyTux
sudo rm -f /etc/default/grub.d/99-flytux.cfg
sudo rm -f /etc/modprobe.d/*flytux*.conf
sudo rm -f /etc/sysctl.d/99-flytux.conf
sudo rm -f /etc/udev/rules.d/60-flytux-io.rules

# 3. Resetear firewall
sudo ufw --force reset && sudo ufw disable

# 4. Desactivar RustDesk pre-login
sudo systemctl disable rustdesk.service

# 5. Restaurar GRUB y reiniciar
sudo update-grub && sudo reboot
```

---

## 🔄 Actualizar FlyTux Optimizer

```bash
# Si ya tienes el repositorio clonado:
cd ~/Flytux-Linux-Optimizer
git pull origin main
chmod +x "FlyTux Optimizer.sh"
sudo "./FlyTux Optimizer.sh"
sudo reboot
```

---

## 📁 Estructura del Repositorio

```
Flytux-Linux-Optimizer/
├── FlyTux Optimizer.sh      # Script principal de optimización
├── README.md                # Documentación completa
├── LICENSE                  # Licencia MIT
└── .github/                 # Configuración de GitHub (issues, workflows)
```

---

## ⚠️ Notas Importantes

> [!CAUTION]
> - **Ejecutar siempre como root**: `sudo "./FlyTux Optimizer.sh"`
> - **Reiniciar es obligatorio**: Los cambios de kernel, GRUB y drivers requieren reinicio
> - **Backup automático**: Se crea en `/tmp/flytux-backup-YYYY-MM-DD.tar.gz`
> - **Logs detallados**: Consulta `/var/log/flytux-*.log` para diagnóstico

> [!TIP]
> - **Primera vez**: Prueba en una máquina virtual con snapshot antes de aplicar en producción
> - **Portátiles**: El perfil de máximo rendimiento (`C-states OFF`) consume más batería
> - **Solo Debian/Ubuntu**: Compatible con Debian 11/12, Ubuntu 20.04-24.04, Linux Mint, Pop!_OS, Zorin OS

---

## 🤝 Contribuir

```bash
# 1. Fork del repositorio
# 2. Clonar tu fork
git clone https://github.com/TU_USUARIO/Flytux-Linux-Optimizer.git

# 3. Crear rama para tu feature
git checkout -b feature/tu-mejora

# 4. Commit y push
git commit -m "feat: descripción de tu mejora"
git push origin feature/tu-mejora

# 5. Abrir Pull Request en GitHub
```

---

## 📄 Licencia

```text
MIT License - FlyTux Optimizer v1.0
Copyright (c) 2026 Gridacorp Contributors

Se concede permiso gratuito para usar, copiar, modificar, fusionar, publicar,
distribuir, sublicenciar y/o vender copias del Software.

EL SOFTWARE SE PROPORCIONA "TAL CUAL", SIN GARANTÍA DE NINGÚN TIPO.
```

---

## 🙏 Apoya el Proyecto

[![Donar con PayPal](https://www.paypalobjects.com/es_ES/ES/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/donate/?hosted_button_id=DMREEX4NSS7V4)

- 🐛 Reporta bugs: [Issues](https://github.com/gridacorp/Flytux-Linux-Optimizer/issues)
- 💡 Sugiere mejoras: [Discussions](https://github.com/gridacorp/Flytux-Linux-Optimizer/discussions)
- 📝 Mejora la documentación: Envía un Pull Request

---

<div align="center">

> 🐧 *"Haz que tu Linux vuele — seguro, compatible y sin límites."*  
> **FlyTux Optimizer v1.0** — Hecho con ❤️ para la comunidad Linux.

[![GitHub Stars](https://img.shields.io/github/stars/gridacorp/Flytux-Linux-Optimizer?style=flat)](https://github.com/gridacorp/Flytux-Linux-Optimizer/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/gridacorp/Flytux-Linux-Optimizer?style=flat)](https://github.com/gridacorp/Flytux-Linux-Optimizer/network/members)
[![License](https://img.shields.io/github/license/gridacorp/Flytux-Linux-Optimizer)](LICENSE)

```bash
# ¿Listo para optimizar?
git clone https://github.com/gridacorp/Flytux-Linux-Optimizer.git && \
cd Flytux-Linux-Optimizer && \
chmod +x "FlyTux Optimizer.sh" && \
sudo "./FlyTux Optimizer.sh" && \
sudo reboot
```

<p align="center">
  <sub>Última actualización: Mayo 2026 • Compatible con Debian 11/12, Ubuntu 20.04-24.04</sub><br>
  <sub>¿Problemas? Abre un <a href="https://github.com/gridacorp/Flytux-Linux-Optimizer/issues">issue</a> con tu log de /var/log/flytux-*.log</sub>
</p>

</div>
