# Manifesto de fontes fixadas (M1)

Gerado em: **2026-11-16** a partir de consultas `git ls-remote`, clones locais em `sources/` e leitura direta dos arquivos do port. Nenhum artefato compilado neste passo; apenas resolução de origens, commits e hashes de patches.

## Repositórios fixados

| Componente | URL | Ref / Critério | Commit completo (SHA-1) | Checkout local | Observação |
| --- | --- | --- | --- | --- | --- |
| Port r8s | `https://github.com/bshbsh404/galaxy-s20fe-mainline-linux` | `main` (`HEAD`) | `e21bfa3f0fd2f15e9e5b0919df44b61d6faba217` | `sources/port` | Contém 24 patches de kernel, `r8s.config`, 15 patches Mesa, `tools/`, `device/` |
| Kernel base | `https://github.com/exynos990-mainline/linux` | `refs/heads/exynos990-fu` (indicado em `docs/BUILDING.md`) | `75138397b8f856193bf344a21a1e1e98179f0901` | `sources/linux` | Base `6.12.0-rc5`; `HEAD` do repo aponta para `ufs-testing` (`dc06c81e108fdcb3a085a861e705f63acf1ca253`), **não** usar sem revalidação |
| uniLoader | `https://github.com/ivoszbg/uniLoader` | `2418e06` (indicado em `docs/BUILDING.md`) | `2418e06635e931e31c74833b8809415fa9695b79` | `sources/uniLoader` | `HEAD` atual do upstream é `0bd1dd1b55420bebf6ddf24a4e46b16372ae53fb`; mantido o pin do port (`r8s_defconfig` presente) |
| lk3rd | `https://github.com/exynos990-mainline/lk3rd` | `refs/heads/dev` (`HEAD`) | `b460741e3adeb1353e2d9597c39badc23467b4fe` | `sources/lk3rd` | Upstream declara inativo; `BOOT_BASE` usa buffer `SZ_64M` (`0x04000000`) e fastboot `0x30000000` (768 MiB) |
| Mesa | `https://gitlab.freedesktop.org/mesa/mesa` | `mesa/README.md` do port | `7d6bb09d5b59ec5af1a58971f34390a62943bfe0` | `sources/mesa` | Série de 15 patches em `sources/port/mesa/patches/` |
| AOSP mkbootimg | `https://android.googlesource.com/platform/system/tools/mkbootimg` | `HEAD` / `main` | `d2bb0af5ba6d3198a3e99529c97eda1be0b5a093` | `sources/mkbootimg` | Usado em `tools/package-boot.sh` |
| Omarchy | `https://github.com/omacom/omarchy` | `refs/tags/v4.5.0^{}` / `refs/heads/quattro` | `ac2690cd7be4f47e4a255f5e2e78d904d436b068` (tag `v4.5.0`, objeto tag `97e664bd971fa5a8691d89440d3738143499c438`) / `3b36b9e19ea00a6c21492098308a7f44a8091564` (`quattro`) | Ainda não clonado | Canal `stable` publica `4.5.0-3`; canal `edge` publica `quattro` (`g3b36b9e`) |
| Omarchy ISO | `https://github.com/omacom/omarchy-iso` | `refs/heads/quattro` (`HEAD`) | `c6790ac8e6cd8b1e2f5396e7ce1489a8c96d96d8` | Ainda não clonado | Referência para `configs/pacman-online-aarch64-stable.conf` e fluxo `[platform]` |
| Omarchy Pkgs | `https://github.com/omacom/omarchy-pkgs` | `refs/heads/master` (`HEAD`) | `7957b7cca9afd0777b776e9bf65bbd275f636431` | Ainda não clonado | PKGBUILDs de `omarchy`, `omarchy-settings`, `hyprland`, `quickshell` |
| wvkbd (candidato OSK) | `https://github.com/jjsullivan5196/wvkbd` | `HEAD` | `4ae78249f39e1c9ce67a939d338aab2ad1e3d919` | Ainda não clonado | Ausente dos repos `omarchy-stable` e ALARM; exige PKGBUILD próprio se escolhido sobre `squeekboard` |
| LineageOS r8s (ref M6) | `https://github.com/LineageOS/android_device_samsung_r8s` | `refs/heads/lineage-24.0` | `1dcaf8f41ff1d82f04bae1d932aff4c44ba4c273` | Ainda não clonado | Referência documental para M6 |
| LineageOS 9830 common (ref M6) | `https://github.com/LineageOS/android_device_samsung_universal9830-common` | `refs/heads/lineage-24.0` | `f8db0251719ed30b92ce6765611af5c4d1826ead` | Ainda não clonado | Referência documental para M6 |
| LineageOS kernel 9830 (ref M6) | `https://github.com/LineageOS/android_kernel_samsung_universal9830` | `refs/heads/lineage-24.0` | `97369af7bbd66581d3e993fea083f3eed02d3c20` | Ainda não clonado | Kernel 4.19.325 (referência M6) |

## Entradas pendentes de extração local / autorização

| Entrada | Origem esperada | Estado | Motivo |
| --- | --- | --- | --- |
| `slk-stock.dtb` | Partição `boot` stock do SM-G780F alvo (`G780FXXSOFYJ2`, `ZTO`, `boot.img` SHA-256 `b33380a1aaf6be060bf2daad042b5c9c820105f3e3f03059c08d4551508a6487`) | `EXTRAÍDO EM blobs/` | `340952` bytes, SHA-256 `30c5769030bd4f801791c7888f8eb57ebc9e8fd944b88972800219d0355ab3f1` (`blobs/slk-stock.dtb`) |
| Firmware Wi-Fi QCA6390 (`amss.bin`, `m3.bin`, `board-2.bin`, `Notice.txt`) | Pacote host `linux-firmware-atheros 20261019-1` (`/usr/lib/firmware/ath11k/QCA6390/hw2.0/*.zst`) | `EXTRAÍDO EM blobs/` | `amss.bin`: `8ab2a06422e3989012df423bb6a156fde2c3feb4cd5db4c5d3588f674dc872ff`; `m3.bin`: `1921d25edb52f90a7a0acc7275861e14399f904d579aae9f7ab1c4d28533fad6`; `board-2.bin`: `4aa9f0fe15e9e2b6f9bb13b7187ed8ce035d9d46fb65fac5d5eba2c4e7edc091`; `Notice.txt`: `2facd28901420b9b58248ec3c17d4ea4693165b72f36106d5537ea4bb9380f1b` |

## Série de patches do kernel (`sources/port/kernel/patches/`, 24 arquivos)

| Ordem | Arquivo | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| 01 | `0001-M0-apply-z3s-working-tree-patch-SoC-stack-on-exynos9.patch` | 72800 | `062e19ccd1fce72dc17bc67b53efa6901973c5f0a430cd8ca2145edf75895c4e` |
| 02 | `0002-M0-install-z3s-device-drivers-upstream-ACPM-backport.patch` | 113860 | `c5dd12c892b61f078e7aa9a5d36acfe7fa4ba106307b962502a354823eeda1bd` |
| 03 | `0003-M0-exynos990-r8s.dts-v0-8GB-memory-map-native-FB-key.patch` | 7237 | `ec3e17b705bdf2186fc7a7fcc43a08a427bee58f89e1710b417bb1cf68484bb3` |
| 04 | `0004-M0-first-clean-build-__counted_by_ptr-backport-shim-.patch` | 5302 | `912428da8637a01c70cf8cc8de45eeea6dbaa9e237b8b34c6cea59879bc91423` |
| 05 | `0005-r8s-display-USB-C-touch-suspend-and-platform-drivers.patch` | 152019 | `d3c107d5f9f3f85c94a0ab04c0579e4436a092cc3542bea37cc7c560ba251fc7` |
| 06 | `0006-arm64-dts-exynos990-mark-the-GPU-IO-coherent-and-all.patch` | 5414 | `3887a3a1eb3c0f292d2a16a5bcec10b8dfdcdb8a8183df929c8e105d5c62deda` |
| 07 | `0007-drm-panfrost-split-the-coherency-flag-into-diagnosti.patch` | 6548 | `305cadb63130b69e6c8b9e6389fe2bc880bafc429a37133edffcee5d0a214baa` |
| 08 | `0008-drm-exynos990-dpu-take-the-DMA-row-length-from-the-f.patch` | 8238 | `58c508835afa9e5915b178fca48e09ac0550dbb903e04d2c85b32f943a8cfeb7` |
| 09 | `0009-cpufreq-exynos990-name-the-cluster-when-an-ACPM-DVFS.patch` | 1171 | `1b2e6aee6f33dad7c5b871a2ad424c2988ea14743b041aef491c38b619d063fe` |
| 10 | `0010-arm64-dts-exynos990-r8s-enable-GICv3-pseudo-NMI-back.patch` | 1159 | `bbf6c75d128a706f8ff342dc923bf9ae1f6f26c1b3343d09ac56ca9aaebe97f6` |
| 11 | `0011-exynos990-ACPM-single-slot-race-fix-CL2-ladder-cappe.patch` | 6861 | `d612c3f4b590bdf7837c40edf227da5bb0656ba79b25bee634824a2980db151b` |
| 12 | `0012-arm64-dts-exynos990-r8s-diagnostic-bootargs-verbose-.patch` | 1429 | `33a78a5c17601e3b2e6a19ddd0ebb8829fa2e1ba8c09329431ebdc6fa4e7756c` |
| 13 | `0013-soc-samsung-exynos990-cpu-wake-arm-PMU-wake-interrup.patch` | 12210 | `34cdabf0fcf8a3f745f9c8112a8e94fddfa173fe6ec5c93b76cb7a1865b950e5` |
| 14 | `0014-arm64-dts-exynos990-add-the-MCT-and-mark-the-C2-idle.patch` | 3751 | `3c7feae743e4d322faaba097c427dd846adf849c56942126f3af9143245cd373` |
| 15 | `0015-soc-samsung-exynos990-cpu-wake-serialise-the-shared-.patch` | 3115 | `25c683dde9bff12ec911fb41f8ce5b34afef2446cdb32685a32ec296d769eea1` |
| 16 | `0016-arm64-dts-exynos990-put-local-timer-stop-on-C2-state.patch` | 1987 | `40d4e15d3f49ca0fc451864d2af3938ec29ad6145bff38f779e120b82e65c1d5` |
| 17 | `0017-soc-samsung-document-actual-cpu-wake-notifier-race-s.patch` | 1985 | `26f185b8a1702c3cdc1bb1b424bacf98ee72fabde2dca37e44b42a4bd43a9955` |
| 18 | `0018-arm64-suspend-rebuild-the-MPIDR-hash-if-it-collides-.patch` | 6398 | `e8b3730dbbaa43482da6f4684792de7239bf179f66e3cc16671a1f584a5e87ef` |
| 19 | `0019-cpuidle-psci-keep-the-CPUs-that-have-idle-states-whe.patch` | 2446 | `4337c44c443585d34a80767826e8d26f1d975ff1b640846e472fd01e5be346d1` |
| 20 | `0020-r8s-cpufreq-warning-tunable-GPU-job-timeout-QCA6390-.patch` | 8086 | `a442d015c7a3c32bd5ccd351ece8fd2fc5c42310ceaac746dc3159ff928f52a9` |
| 21 | `0021-btqca-QCA6390-in-this-handset-answers-TLV-segments-i.patch` | 6870 | `4bc8c55e67fd268ba4f9ca27a1cb1a9188bf22e4a063ee0e2c2c427f61dfad42` |
| 22 | `0022-Bluetooth-btqca-check-QCA6390-Command-Complete-downl.patch` | 4538 | `17be7e768a789a00c1c794c22e5120f7fd8e3957e53114e621372386fee6f7c0` |
| 23 | `0023-u_ether-stop-ethtool-following-a-pointer-that-outliv.patch` | 4412 | `bc20680214d7b792d4d1ec4fb2f49542b16e8cb52a3562d5044d84433dcd3351` |
| 24 | `0024-arm64-dts-exynos990-r8s-keep-firmware-owned-RAM-out-.patch` | 3640 | `9050b31e6ac3e7a03fd5d27fc28a669c0bad78adcba9b36fb2d494ed24c1267c` |

## Série de patches do Mesa (`sources/port/mesa/patches/`, 15 arquivos)

| Ordem | Arquivo | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| 01 | `0001-panvk-baseline-Valhall-v9-Mali-G77-JM-enablement-fro.patch` | 126972 | `661cbee827bbd984ca1a7212cb3b0617ba0e2e3bfe14d156da52c67a09baeaa8` |
| 02 | `0002-vulkan-runtime-add-a-compute-shader-BCn-BC1-BC5-deco.patch` | 30093 | `6a93c7b0f628c88a1e0c6721f8de470326e3bd61fa72ec27b9ac10f9f8f0bca0` |
| 03 | `0003-panvk-gate-and-advertise-BCn-emulation-PANVK_BC_EMUL.patch` | 10467 | `874a23e048e054ad381c6f4f3df99cbe451d07063818c632b97d690895cffdef` |
| 04 | `0004-panvk-back-BC-emulated-images-with-a-raw-block-plane.patch` | 6049 | `4078b19798ea286448ce6a74107c9162dc34d3b8e32b236079ef891ab19f8fa4` |
| 05 | `0005-panvk-decode-BC-blocks-with-a-compute-dispatch-after.patch` | 16541 | `cbf13fc98dd6ce28c4b2540c276d59cdd14aefeb465c1f2c3a50326f04fd4dfe` |
| 06 | `0006-vulkan-runtime-pin-the-BCn-decoder-arithmetic-to-the.patch` | 13319 | `46704df09e46cd83c917d093a15a75d46f4caf79523a2be7df36c609a20623b6` |
| 07 | `0007-panvk-add-a-PANVK_DXVK_COMPAT-gate-and-advertise-the.patch` | 8069 | `7b7c27704f3c85e642d4faf641701ed69a72bde503fac1b8bf179e8060f077e4` |
| 08 | `0008-panvk-implement-shaderClipDistance-on-v9-as-a-fragme.patch` | 10684 | `6ccbfa5254df59bef327c353d7293949651d666675bd3fe96ee7447e4452d2cd` |
| 09 | `0009-panvk-enable-VK_KHR-EXT_robustness2-on-v9-under-PANV.patch` | 5629 | `b5b3bc89aa83f2bde8b489f6177ed6cbbafe318c35c7ce3ff6eb4a70682a6e21` |
| 10 | `0010-panfrost-bifrost-lower-ubfe-ibfe-in-NIR.patch` | 8923 | `742320808e96ae31386053f7219f4354c43f0717b5c681fc9bc911e1c3eb6ff7` |
| 11 | `0011-panfrost-bifrost-test-the-ubfe-ibfe-lowering-against.patch` | 11479 | `bbb793333981e65bc94f637b4cc0e7d07d71f39ea84b1201467786629aacd32b` |
| 12 | `0012-compiler-glsl-add-BC7-and-BC6H-compute-decoders-from.patch` | 51435 | `10ce3f31fd96590fb79732707d6af44ea5333d7ac47f434f1f4cbbdac7395697` |
| 13 | `0013-vulkan-runtime-decode-BC7-and-BC6H-in-vk_texcompress.patch` | 38865 | `49e4d03c05fc29ae7ac081c0664a56e394d064f466fb0330e0fe1609f872570a` |
| 14 | `0014-vulkan-runtime-pin-the-BC7-BC6H-decoders-to-the-CPU-.patch` | 29175 | `720563df065a2363d25ac408b0f05208c4edbeec19f1ea83400b4a6c5dc4bf72` |
| 15 | `0015-panvk-dispatch-the-BC7-BC6H-decode-pipelines-add-PAN.patch` | 7809 | `45dc7f9abbe4c116a0d2b056c84af35fcc5b79b543213eb60e09367b91454901` |
