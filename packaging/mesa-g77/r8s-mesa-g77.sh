# Side-by-side Mesa 26.3.0-devel (Panfrost + PanVK Valhall v9 / Mali-G77)
# Installed in /opt/mesa-g77 on Arch Linux ARM (r8s / Exynos 990).
# Derived from sources/port/device/r8s-mesa-glx.sh, adapted for Arch /opt/mesa-g77/lib.

MESA_G77_PREFIX=/opt/mesa-g77

case ":${LD_LIBRARY_PATH:-}:" in
  *:"$MESA_G77_PREFIX/lib":*) ;;
  *) export LD_LIBRARY_PATH="$MESA_G77_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
esac

export __EGL_VENDOR_LIBRARY_FILENAMES="$MESA_G77_PREFIX/share/glvnd/egl_vendor.d/50_mesa.json"
export LIBGL_DRIVERS_PATH="$MESA_G77_PREFIX/lib/dri"
export GBM_BACKENDS_PATH="$MESA_G77_PREFIX/lib/gbm"
export VK_DRIVER_FILES="${VK_DRIVER_FILES:-$MESA_G77_PREFIX/share/vulkan/icd.d/panfrost_icd.aarch64.json}"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-$MESA_G77_PREFIX/share/vulkan/icd.d/panfrost_icd.aarch64.json}"

# Required on Exynos 990 DPU + Mali-G77 to avoid AFBC scanout/compositing faults.
export PAN_MESA_DEBUG="${PAN_MESA_DEBUG:-noafbc}"

# PanVK on Valhall v9 (job-manager) is gated as experimental in Mesa 26.3.0-devel.
export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER="${PAN_I_WANT_A_BROKEN_VULKAN_DRIVER:-1}"

# Experimental PanVK gates from sources/port/device/r8s-mesa-glx.sh (patches 0002-0015).
# Kept opt-in for desktop sessions because PANVK_DXVK_COMPAT=1 advertises
# geometryShader without implementing GS pipelines (4-8x memory cost for BCn).
# Set R8S_PANVK_EXPERIMENTAL=1 or use mesa-g77-run --dxvk for DXVK/Vulkan workloads.
if [ "${R8S_PANVK_EXPERIMENTAL:-0}" = "1" ]; then
  export PANVK_BC_EMULATION="${PANVK_BC_EMULATION:-1}"
  export PANVK_DXVK_COMPAT="${PANVK_DXVK_COMPAT:-1}"
fi

unset MESA_G77_PREFIX
