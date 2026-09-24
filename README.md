# FoldingBook 💻✨

Physical lid-angle-driven folding display effect for your MacBook. As you lower your screen, your real desktop content dynamically tilts in perspective to compensate for physical hinge inclination, accompanied by a progressive, GPU-accelerated Gaussian blur powered by Metal.

Optimized and verified for **MacBook Air M4** (Apple Silicon, macOS Sonoma / Sequoia).

---

## 🚀 Quick Start

### 1. Run the application
To compile and launch the background menu bar application:

```bash
./scripts/run.sh
```

The app will appear in your macOS menu bar with a MacBook icon (or showing live hinge degrees if HUD mode is enabled).

### 2. Global Shortcut and Controls
- **Global Shortcut:** Press `⌃⌘L` (`Control + Command + L`) to toggle the effect on or off at any time.
- **Left-click on menu bar icon:** Toggle the folding effect.
- **Right-click on menu bar icon:** Open configuration menu:
  - **Activate at or below:** Configure the hinge threshold angle where the fold activates (defaults to 100°).
  - **Jitter tolerance:** Sensor noise filter (0° for maximum responsiveness).
  - **Progressive Blur:** Depth-based Gaussian blur powered by Metal Performance Shaders.
  - **Hold Visual Plane:** Keeps the desktop plane fixed while the lid rotates.
  - **Perspective Projection:** Dynamic projective perspective taper.
  - **Show Lid Angle in Menu Bar:** Displays real-time sensor angle directly in the menu bar.
  - **Simulate a Fold:** Test the shader and visual warping immediately without physically moving your laptop screen.

---

## 🔒 Required Permissions (Screen Recording)

To capture live desktop frames and render the distortion and progressive blur in real time with ScreenCaptureKit, macOS requires Screen Recording permission:

1. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Ensure **FoldingBook** is toggled ON.
3. If macOS prompts that the application will not have permissions until it restarts, click **Quit & Reopen** (or let launchd restart it automatically).

---

## ⚡ 100% Uptime Autostart Service

To keep FoldingBook running continuously in the background, surviving app crashes, sleep/wake cycles, and system reboots:

### Install as a permanent service (LaunchAgent):

Run the automated installer:

```bash
./scripts/install_autostart.sh
```

This command:
1. Compiles the optimized production release (`release`).
2. Installs the application bundle into `/Applications/FoldingBook.app`.
3. Registers a persistent **LaunchAgent** at `~/Library/LaunchAgents/com.foldingbook.app.plist` with:
   - `RunAtLoad: true` (automatically launches upon user login).
   - `KeepAlive: true` (`launchd` supervises the process and restarts it instantly if terminated).
   - Redirects output logs to `/tmp/foldingbook.log` and `/tmp/foldingbook_err.log`.

### Uninstall the autostart service:

```bash
./scripts/uninstall_autostart.sh
```

---

## 🛠️ Diagnostics & CLI Utilities

You can test individual subsystems directly from your terminal:

```bash
# Probe the live Apple Silicon HID lid angle sensor
./scripts/run.sh --probe

# Run unit tests (motion policy, jitter filters, and clamshell safety gates)
./scripts/run.sh --test

# Generate Metal shader test preview images in dist/
./scripts/run.sh --preview

# Verify that the app is actively running in background
./scripts/run.sh --verify
```

---

## 📐 Technical Architecture

1. **HID Sensor (IOKit):** Ultra-low-power raw read of the internal MacBook lid angle sensor (`0x05ac / 0x8104 / 0x20 / 0x8a`). Non-invasive hardware query.
2. **ScreenCaptureKit:** Full-resolution Liquid Retina SDR stream (2560x1664 on MacBook Air M4), automatically excluding the overlay window to prevent feedback loops.
3. **Metal Shaders & MPS:** GPU-accelerated 4-level progressive Gaussian blur (`MPSImageGaussianBlur` sigmas 2, 6, 16, 40) mapped to physical distance from the hinge axis.
4. **Transparent Passthrough Overlay:** Floating `.screenSaver` level panel with `ignoresMouseEvents = true`, ensuring full click-through and keyboard transparency for underlying applications.
