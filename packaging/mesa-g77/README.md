# mesa-g77 — Arch Linux ARM (`aarch64`) Packaging & Integration

Side-by-side Mesa `26.3.0-devel` (`Panfrost` + `PanVK` Valhall v9 / Mali-G77) recipe for Samsung Galaxy S20 FE (`SM-G780F` / `r8s` / Exynos 990), installed under `/opt/mesa-g77`.

**Runtime dependency correction (2026-11-17):** inspection with `readelf -d` of the built `pkgrel=1` found `libSPIRV-Tools.so` in both `libgallium` and `libvulkan_panfrost` dependencies. `pkgrel=2` adds `spirv-tools` to `depends` (it was only a build dependency). The existing `-1-aarch64.pkg.tar.xz` does not contain this metadata correction; regenerate the package before using it for installation. This is ELF inspection on the computer, not a GPU test.

Revision 2 has now been repackaged from the existing compilation and installed in an ARM64 container; EGL/PanVK dynamic linking passed. SHA-256 and reproduction limits are in [offline-validation.md](../../manifests/offline-validation.md). GPU operation remains untested.

## 1. Source & Patch Verification

- **Base tree:** [`sources/mesa`](../../sources/mesa) at commit `7d6bb09d5b59ec5af1a58971f34390a62943bfe0` (`VERSION`: `26.3.0-devel`).
- **Patch series:** all 15 patches in [`sources/port/mesa/patches/`](../../sources/port/mesa/patches/) (`0001`–`0015`):
  - `0001`: Valhall v9 (Mali-G77 JM) PanVK baseline enablement (`fillModeNonSolid`)
  - `0002`–`0006`, `0012`–`0015`: BC1–BC7 compute-shader texture decompression (`PANVK_BC_EMULATION=1`, `PANVK_DEBUG=bcn`)
  - `0007`–`0009`: DXVK compatibility gates (`PANVK_DXVK_COMPAT=1`, `shaderClipDistance` fragment discard, `robustness2`)
  - `0010`–`0011`: Bifrost/Panfrost NIR `ubfe`/`ibfe` lowering + unit tests
- **Verified locally (2026-11-17):** all 15 patches apply cleanly without conflicts on `7d6bb09d5b59ec5af1a58971f34390a62943bfe0` in a temporary `/tmp` copy via both `git am` (head `4aba321`) and `patch -Np1`.

## 2. Files in `packaging/mesa-g77/`

| File | Target path in rootfs | Purpose |
| --- | --- | --- |
| [`PKGBUILD`](PKGBUILD) | — | Arch `aarch64` recipe (`--prefix=/opt/mesa-g77 --libdir=lib`) |
| [`r8s-mesa-g77.sh`](r8s-mesa-g77.sh) | `/etc/profile.d/r8s-mesa-g77.sh` | Login/shell environment selecting `/opt/mesa-g77`, `PAN_MESA_DEBUG=noafbc`, and PanVK options |
| [`90-r8s-mesa-g77.conf`](90-r8s-mesa-g77.conf) | `/etc/environment.d/90-r8s-mesa-g77.conf` | `systemd --user` environment inherited by UWSM, Hyprland, Quickshell, Xwayland, portals |
| [`20-r8s-mesa-g77.conf`](20-r8s-mesa-g77.conf) | `/usr/lib/systemd/system/sddm.service.d/20-r8s-mesa-g77.conf` | SDDM service drop-in (since `sddm.service` does not read `profile.d` or `environment.d`) |
| [`mesa-g77-run`](mesa-g77-run) | `/opt/mesa-g77/bin/mesa-g77-run` | Per-command launcher with `--bc`, `--dxvk` / `--panvk-compat`, `--bcn-debug`, `--print-env` |
| [`build-mesa-g77.sh`](build-mesa-g77.sh) | — | Stages `sources/mesa` + patches into `out/build/mesa-g77-pkg` and runs `makepkg` offline |

## 3. Side-by-Side Policy & Dependency Audit (`manifests/packages-aarch64.md`)

`mesa-g77` intentionally **does not** declare `provides=('mesa')` or `conflicts=('mesa')`:

- Stock `extra/mesa` (`1:26.2.5-1` in [`manifests/packages-aarch64-stable.tsv`](../../manifests/packages-aarch64-stable.tsv)) stays installed so `hyprland`, `quickshell`, `qt6-*`, `xorg-xwayland`, `sddm`, and `libglvnd` keep clean pacman SONAME resolution without version skew or broken rebuilds on Arch updates.
- Applications pick up `/opt/mesa-g77` via `LD_LIBRARY_PATH`, `__EGL_VENDOR_LIBRARY_FILENAMES`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH`, `VK_DRIVER_FILES`, and `VK_ICD_FILENAMES`. Do **not** add `/opt/mesa-g77/lib` to `/etc/ld.so.conf.d/`, so stock Mesa remains available for isolation tests.

Checked against [`manifests/packages-aarch64.md`](../../manifests/packages-aarch64.md), [`manifests/packages-aarch64-stable.tsv`](../../manifests/packages-aarch64-stable.tsv), and [`sources/mesa/meson.build`](../../sources/mesa/meson.build):

| Package | Role | Status in `manifests/packages-aarch64-stable.tsv` | Why needed |
| --- | --- | --- | --- |
| `libdrm` | `depends` | `2.4.134-1` (`extra`) | DRM/KMS/Panfrost ioctls |
| `libglvnd` | `depends` | `1.7.0-3` (`extra`) | EGL/GLX dispatch to `50_mesa.json` / `libGLX_mesa.so.0` |
| `wayland` | `depends` | `1.26.0-1` (`extra`) | Wayland EGL/Vulkan WSI |
| `libx11`, `libxcb`, `libxext`, `libxfixes`, `libxshmfence`, `libxxf86vm` | `depends` | All present (`extra`) | `-Dglx=dri` + `-Dplatforms=wayland,x11` (Xwayland GLX/DRI3) |
| `expat`, `zlib`, `zstd`, `glibc`, `gcc-libs`, `systemd-libs` | `depends` | All present (`core`/`extra`) | Core Mesa runtime / udev / shader cache compression |
| `libdisplay-info` | `depends` | `0.3.0-1` (`extra`) | Display/EDID metadata in Vulkan WSI (`-Ddisplay-info=enabled`) |
| `llvm-libs` | `depends` | `libLLVM.so=23.1-64` (`06`/`manifests/packages-aarch64.md:82`) | Linked by `libgallium_dri` (`src/gallium/targets/dri/meson.build:59`) when `-Dllvm=enabled -Dshared-llvm=enabled` |
| `libelf` | `depends` | ALARM `core` (`libelf`) | Optional ELF helper auto-detected by `meson.build:2153` (`src/panfrost/vulkan/meson.build:223`) |
| `llvm`, `clang`, `spirv-llvm-translator`, `spirv-tools` | `makedepends` | ALARM `extra` | Required at build time by `mesa_clc` (`src/compiler/clc/meson.build`, `sources/port/mesa/README.md`) |
| `meson`, `ninja`, `pkgconf`, `bison`, `flex`, `git`, `python-*`, `wayland-protocols`, `xorgproto` | `makedepends` | ALARM `core`/`extra` (`wayland-protocols` `1.49-1` in manifest) | Meson build, NIR/GLSL codegen (`mako`, `yaml`, `packaging`, `ply`), X11/Wayland headers |

Optional features disabled (`-Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dxlib-lease=disabled`) so no unrequested runtime libraries (`libxrandr`, `lm_sensors`, `libunwind`) are linked opportunistically.

## 4. Integration Notes: Hyprland, Aquamarine, Quickshell, SDDM, UWSM

1. **Split DRM topology (`exynos990-dpu` KMS + `panfrost` render node):**
   - `mesa-g77` builds `-Dgallium-drivers=panfrost` (which enables `kmsro` in [`sources/mesa/meson.build`](../../sources/mesa/meson.build#L342) for `exynos990-dpu` scanout + Mali-G77 rendering).
   - Hyprland/Aquamarine still needs `AQ_DRM_DEVICES` pointing to `/dev/dri/cardX:/dev/dri/cardY` (`r8s-detect-drm` in [`packaging/omarchy/install-omarchy-r8s.sh`](../omarchy/install-omarchy-r8s.sh#L105-L135)) and `fbcon` unbound (`r8s-unbind-fbcon.service`) before SDDM starts.
2. **`PAN_MESA_DEBUG=noafbc` is mandatory:**
   - Exported in `/etc/profile.d/r8s-mesa-g77.sh`, `/etc/environment.d/90-r8s-mesa-g77.conf`, and `sddm.service.d/20-r8s-mesa-g77.conf` to avoid AFBC scanout/compositing corruption on Exynos 990 DPU + Panfrost.
3. **Do NOT force `XDG_RUNTIME_DIR=/run/r8s` in Arch desktop sessions:**
   - [`sources/port/device/r8s-mesa-glx.sh`](../../sources/port/device/r8s-mesa-glx.sh#L12) defaulted `XDG_RUNTIME_DIR=/run/r8s` for the single-user Debian console service (`r8s-session.sh`). Under Arch + `systemd-logind` + SDDM + UWSM, `pam_systemd` owns `/run/user/$UID`; overriding it breaks Hyprland, Quickshell, PipeWire, and portal sockets.
4. **Hyprland / Xwayland (`-Dglx=dri`):**
   - `/opt/mesa-g77/lib/libGLX_mesa.so.0` + `/opt/mesa-g77/lib/dri` give Xwayland hardware-accelerated GLX/DRI3.
   - Because `mesa-g77` uses Arch `--libdir=lib` (not Debian multiarch `lib/aarch64-linux-gnu`), all library/DRI/GBM paths live under `/opt/mesa-g77/lib`.
5. **Quickshell / Qt6 (`qt6-wayland`, `qt6-declarative`):**
   - Qt6 Wayland defaults to OpenGL ES / EGL (`QSG_RHI_BACKEND=opengl`) and picks up `/opt/mesa-g77/share/glvnd/egl_vendor.d/50_mesa.json` via `__EGL_VENDOR_LIBRARY_FILENAMES`.
   - Keep `PANVK_DXVK_COMPAT` and `PANVK_BC_EMULATION` **opt-in** (via `mesa-g77-run --dxvk` or `R8S_PANVK_EXPERIMENTAL=1` when sourcing `r8s-mesa-g77.sh`) rather than global defaults: `PANVK_DXVK_COMPAT=1` advertises `geometryShader` without implementing GS pipelines (which returns `VK_ERROR_UNKNOWN` if a Vulkan client uses geometry shaders), and `PANVK_BC_EMULATION=1` incurs 4–8× memory overhead for BCn textures.
6. **SDDM + UWSM inheritance:**
   - `20-r8s-mesa-g77.conf` injects the `/opt/mesa-g77` variables directly into `sddm.service` (systemd `[Service]` `Environment=`), while `90-r8s-mesa-g77.conf` feeds `systemd --user` -> `uwsm` -> `Hyprland` -> `Quickshell` -> apps.

## 5. On-Device Verification Commands

After installing `mesa-g77` on the phone (inside a Wayland session or via `mesa-g77-run`):

```sh
# 1. Confirm hardware GL/EGL renderer (MUST be Mali-G77 (Panfrost), NEVER llvmpipe/softpipe)
eglinfo -B | grep -iE 'vendor|renderer|version'
glxinfo -B | grep -iE 'vendor|renderer|direct rendering'

# 2. Confirm /opt/mesa-g77 DSOs are actually loaded (not /usr/lib/libEGL_mesa.so.0)
LD_DEBUG=libs mesa-g77-run eglinfo -B 2>&1 | grep -E 'calling init: .*/opt/mesa-g77/lib/' | head -n 10
mesa-g77-run --print-env

# 3. Confirm PanVK ICD (Valhall v9 gated by PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1)
mesa-g77-run vulkaninfo --summary

# 4. Run a DXVK / Vulkan workload with experimental BCn + DXVK compat gates
mesa-g77-run --dxvk <command>
```
