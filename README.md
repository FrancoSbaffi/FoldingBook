# FoldingBook 💻✨

Efecto de plegado de pantalla (*folding display*) impulsado en tiempo real por el sensor de ángulo de la bisagra de tu MacBook. Al bajar la pantalla, el contenido del escritorio se proyecta en perspectiva compensando la inclinación física con un desenfoque progresivo (*progressive blur*) de grado GPU mediante Metal.

Optimizado y verificado para **MacBook Air M4** (Apple Silicon, macOS Sonoma / Sequoia).

---

## 🚀 Inicio Rápido

### 1. Ejecutar la aplicación
Para compilar y abrir la app en segundo plano:

```bash
./scripts/run.sh
```

La app aparecerá en tu barra de menús con el ícono de una MacBook (o mostrando los grados en tiempo real si activas el HUD).

### 2. Atajo global y Controles
- **Atajo global:** Presiona `⌃⌘L` (`Control + Command + L`) para activar o desactivar el efecto en cualquier momento.
- **Click izquierdo en la barra de menús:** Activa / desactiva el efecto.
- **Click derecho en la barra de menús:** Abre el menú de configuración:
  - **Activate at or below:** Ajusta el ángulo límite a partir del cual se activa el efecto (por defecto 100°).
  - **Jitter tolerance:** Filtro de vibraciones leves (0° para máxima sensibilidad en reposo).
  - **Progressive Blur:** Desenfoque progresivo gaussiano acelerado por GPU (Metal Performance Shaders).
  - **Hold Content Angle:** Mantiene el plano visual fijo mientras la bisagra física se mueve.
  - **Perspective Taper:** Proyección cónica de perspectiva.
  - **Show Lid Angle in Menu Bar:** Muestra los grados exactos del sensor en la barra de menús en tiempo real.
  - **Simulate a Fold:** Prueba el efecto inmediatamente sin necesidad de mover físicamente la pantalla.

---

## 🔒 Permisos Requeridos (Screen Recording)

Para capturar la pantalla y aplicar la distorsión y desenfoque en tiempo real con ScreenCaptureKit, macOS requiere permiso de grabación de pantalla:

1. Ve a **Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema** (*Screen & System Audio Recording*).
2. Asegúrate de habilitar **FoldingBook**.
3. Si acabas de compilar la app por primera vez, macOS te pedirá autorización al encender el efecto. Simplemente concédela y reinicia la app.

---

## ⚡ Cómo mantenerlo funcional el 100% del tiempo

Para que FoldingBook esté activo **siempre**, incluso después de reiniciar la Mac o si el proceso se cierra inesperadamente:

### Instalación como servicio permanente (LaunchAgent):

Ejecuta el script de instalación automática:

```bash
./scripts/install_autostart.sh
```

Este comando:
1. Compila la versión optimizada de producción (`release`).
2. Instala la app en `/Applications/FoldingBook.app`.
3. Registra un **LaunchAgent** en `~/Library/LaunchAgents/com.foldingbook.app.plist` con:
   - `RunAtLoad: true` (se inicia automáticamente al encender o iniciar sesión).
   - `KeepAlive: true` (`launchd` monitoriza el proceso y lo relanza de forma automática e inmediata si se detiene).

### Para desinstalar el servicio permanente:

```bash
./scripts/uninstall_autostart.sh
```

---

## 🛠️ Comandos de Diagnóstico y Pruebas

Puedes probar cada subsistema de forma independiente desde la terminal:

```bash
# Probar la lectura en vivo del sensor de la bisagra (Apple Silicon HID)
./scripts/run.sh --probe

# Ejecutar las pruebas unitarias de política de movimiento, filtros y seguridad
./scripts/run.sh --test

# Generar imágenes de muestra del shader de Metal en dist/
./scripts/run.sh --preview

# Verificar que la app esté corriendo en segundo plano
./scripts/run.sh --verify
```

---

## 📐 Arquitectura Técnica

1. **Sensor HID (IOKit):** Lectura directa de bajo consumo del sensor de ángulo de la bisagra (`0x05ac / 0x8104 / 0x20 / 0x8a`). Sin accesos intrusivos.
2. **ScreenCaptureKit:** Flujo de fotogramas a resolución nativa SDR Liquid Retina (2560x1664 en MacBook Air M4), excluyendo automáticamente la propia ventana de la app para evitar bucles de captura (*hall of mirrors*).
3. **Metal Shaders & MPS:** Renderizado en GPU con 4 niveles de desenfoque gaussiano progresivo (`MPSImageGaussianBlur` sigmas 2, 6, 16, 40) vinculados a la distancia física respecto a la bisagra.
4. **Ventana Overlay Clickeable:** Panel flotante transparente a nivel `.screenSaver` con `ignoresMouseEvents = true`, permitiendo que todos los clicks del ratón y atajos del teclado sigan interactuando normalmente con tus aplicaciones subyacentes.
