# Manifesto de artefatos compilados (M1)

Verificado localmente em: **2026-11-17** por `checks/verify-m1-m4-artifacts.sh` e `packaging/host-tools/m2-preflight.sh` (após rebuild com `mini`, `package` e correções de serviços/permissões em `ufs-root.img`). Todos os valores abaixo foram **observados nos artefatos em `out/` e `blobs/`**; **nenhum artefato foi gravado ou executado no SM-G780F neste estágio**.

## Kernel e cadeia de boot

- `kernelrelease`: **`6.12.0-rc5-next-20241104-r8s`** (lido de `out/boot/kernel-release.txt`)
- Fontes fixadas em [sources.md](sources.md): kernel `75138397b8f856193bf344a21a1e1e98179f0901` + 24 patches do port `e21bfa3f0fd2f15e9e5b0919df44b61d6faba217`, uniLoader `2418e06635e931e31c74833b8809415fa9695b79`, lk3rd `b460741e3adeb1353e2d9597c39badc23467b4fe`, AOSP mkbootimg `d2bb0af5ba6d3198a3e99529c97eda1be0b5a093`.

## Artefatos em `out/`

| Caminho | Bytes | SHA-256 | Papel / limite verificado |
| --- | ---: | --- | --- |
| `out/boot/Image` | 27291656 | `2ad04d4994d2b99d5fc935438bf106c0ae5b544eb6eabb18342f10f765a9a6c7` | Kernel ARM64 compilado (`6.12.0-rc5-next-20241104-r8s`) |
| `out/boot/exynos990-r8s.dtb` | 83065 | `c406ea4e6c281c5e9ac89b3378779f02c04ce034a5c54e24dc43079f067a8c95` | DTB mainline (`0xd00dfeed`, ajuste 6 GB `0100-*`), embutido no uniLoader |
| `out/boot/kernel.config` | 226720 | `97686ac4f7c699e72462d75b111d1c1a20648c59294481a05a4b66945da2a176` | `.config` resultante de `r8s.config` + `olddefconfig` |
| `out/boot/kernel-release.txt` | 43 | `47370f4c0aee5eb517f3e0b8241e18d9ff0fead29d66cdebb06c052e9233414e` | Registro `kernelrelease=6.12.0-rc5-next-20241104-r8s` |
| `out/boot/kernel.sha256` | 306 | `a092b8a258880a7121e246d0e440a9d62ea50830ace19461089d0335b16161aa` | Checksums de `Image`, `exynos990-r8s.dtb` e tarball de módulos |
| `out/modules-6.12.0-rc5-next-20241104-r8s.tar.gz` | 8271827 | `9413d24ae9eda891cf1ff63f68ccca40c62d643e3c36cbdc03c5162489dbdd56` | Módulos do mesmo build (`./modules.dep` presente) |
| `out/boot/lk3rd-r8s.img` | 2097152 | `48a15319a0ee3dcb65faaacaf51bd4bb897925c5efc03d19543eaa4afc4286ab` | Bootloader secundário r8s (`<= 2097152` B / 2 MiB) |
| `out/boot/lk3rd-r8s.tar` | 573440 | `d999b844426f229742019b1cadf154ac95a90251a598dfa6708ee1ec1185c0e5` | Pacote Heimdall/Odin de `lk3rd-r8s.img` para Download mode |
| `out/boot/lk3rd-r8s.sha256` | 190 | `27e403eb7cac1a7899a7b4c5d2df50501a3e7b13bbd069d1c47da5fd758f1e58` | Checksums de `lk3rd-r8s.img` e `.tar` |
| `out/boot/initramfs-slim.cpio.gz` | 37725548 | `fc172473176ba513cce504b893f0d277d08ed56ed4e68a048a92b33df166ee60` | Initramfs Debian `trixie` slim (teste em RAM; `gzip -t` ok) |
| `out/boot/initramfs-slim.sha256` | 104 | `fcb2175e23142eb82a4c214142ec76f3a7552747b3ada011593a3a2e92e98004` | Checksum de `initramfs-slim.cpio.gz` |
| `out/boot/initramfs-mini.cpio.gz` | 1016955 | `7c3e26f1c985221bd1ae0bfdac9dffd93d2edeb3e2bd2ebad4733e6293beb649` | Initramfs mínimo BusyBox/diagnóstico USB (`gzip -t` ok) |
| `out/boot/initramfs-mini.sha256` | 104 | `b2956497f45ddc604c4f9e51a9eef5f44eab210d0d6e3cce41aede742c3613d4` | Checksum de `initramfs-mini.cpio.gz` |
| `out/boot/r8s-ram.img` | 65509376 | `cc942728037c3a3eab935cfef1d9b8f81a452a49c929321c19d5c600f4d305dc` | Imagem de teste em RAM (`<= 67108864` B / 64 MiB do buffer `lk3rd`) |
| `out/boot/r8s-ram.sha256` | 93 | `729477c524abf206c33fcdf4048df93a4d2c3229a7656f81612a07edd3b259d1` | Checksum de `r8s-ram.img` |
| `out/boot/r8s-mini.img` | 28801024 | `ce095b7fd907b125284e770cd5b35daa5910fc7f15facf35b20b79cfb5704fc3` | Imagem de diagnóstico mínimo em RAM (`<= 67108864` B) |
| `out/boot/r8s-mini.sha256` | 94 | `493df0ca7b3a6bab5816566d9ce2d21f5cdbd7cbe36650c1957fe967d6d28f14` | Checksum de `r8s-mini.img` |
| `out/boot/r8s-ufs.img` | 27785216 | `eeeefac7039f1618c64f9bf142ce6f09d5da00019afe860d0a990e1fcea763aa` | Imagem persistente para rootfs em UFS (`root=/dev/sda32`) |
| `out/boot/r8s-ufs.sha256` | 93 | `c42af3abbaa53a3659f92a2e2c1bbd16a7b79a69607eab151fc5d66e533d4407` | Checksum de `r8s-ufs.img` |
| `out/rootfs/ufs-root.img` | 734003200 | `349c999e50a3157c003dd1de392dee69ba12c510f42bf91c03279274c060c112` | Rootfs ext4 Arch Linux ARM mínimo (`<= 734003200` B / 700 MiB) |
| `out/rootfs/ufs-root.sha256` | 96 | `ae568005b611ad66d0c3266c2e2c2591104043ea024b8ee5b72d3491ce7ff154` | Checksum de `ufs-root.img` |
| `out/rootfs/arch-base-packages.txt` | 3064 | `ad3ce62702b84670b06759cd7d18f204c9f10a7f96892cb972afd71fe2b00fa8` | 160 pacotes AArch64 instalados; sem pacote `linux-*` de kernel |

## Blobs locais em `blobs/` (fora do Git)

| Caminho | Bytes | SHA-256 | Origem / papel |
| --- | ---: | --- | --- |
| `blobs/slk-stock.dtb` | 340952 | `30c5769030bd4f801791c7888f8eb57ebc9e8fd944b88972800219d0355ab3f1` | Extraído de `G780FXXSOFYJ2` (`boot.img`); vai no header Android v2 |
| `blobs/firmware/ath11k/QCA6390/hw2.0/amss.bin` | 3628672 | `8ab2a06422e3989012df423bb6a156fde2c3feb4cd5db4c5d3588f674dc872ff` | Pacote host `linux-firmware-atheros` (`QCA6390/hw2.0`) |
| `blobs/firmware/ath11k/QCA6390/hw2.0/board-2.bin` | 231980 | `4aa9f0fe15e9e2b6f9bb13b7187ed8ce035d9d46fb65fac5d5eba2c4e7edc091` | Pacote host `linux-firmware-atheros` (`QCA6390/hw2.0`) |
| `blobs/firmware/ath11k/QCA6390/hw2.0/m3.bin` | 266684 | `1921d25edb52f90a7a0acc7275861e14399f904d579aae9f7ab1c4d28533fad6` | Pacote host `linux-firmware-atheros` (`QCA6390/hw2.0`) |
| `blobs/firmware/ath11k/QCA6390/hw2.0/Notice.txt` | 189707 | `2facd28901420b9b58248ec3c17d4ea4693165b72f36106d5537ea4bb9380f1b` | Aviso de licença QCA6390 (`linux-firmware-atheros`) |

## Inspeção estrutural (observada fora do aparelho)

1. **Cabeçalhos Android v2 (`sources/mkbootimg/unpack_bootimg.py`)**:
   - `out/boot/r8s-ram.img`: `boot magic: ANDROID!`, `header version: 2`, `page size: 2048`, `kernel_size: 65163080` (`uniLoader` com `Image` + `exynos990-r8s.dtb` + `initramfs-slim.cpio.gz`), `ramdisk size: 20` (placeholder gzip vazio; sem dupla compactação), `dtb size: 340952`.
   - `out/boot/r8s-mini.img`: `boot magic: ANDROID!`, `header version: 2`, `page size: 2048`, `kernel_size: 28454488` (`uniLoader` com `Image` + `exynos990-r8s.dtb` + `initramfs-mini.cpio.gz`), `ramdisk size: 20`, `dtb size: 340952`.
   - `out/boot/r8s-ufs.img`: `boot magic: ANDROID!`, `header version: 2`, `page size: 2048`, `kernel_size: 27437552` (`uniLoader` com `Image` + `exynos990-r8s.dtb` + placeholder gzip vazio), `ramdisk size: 20`, `dtb size: 340952`.
   - `out/boot/lk3rd-r8s.img`: `boot magic: ANDROID!`, `header version: 2`, `page size: 2048`, `kernel_size: 620872`, `ramdisk size: 19`, `dtb size: 340952`, `command line args: LK3RD BOOT IMAGE`.
2. **Filesystem e permissões de `out/rootfs/ufs-root.img`**:
   - `e2fsck -fn`: `r8sroot: 16307/44832 files (0.2% non-contiguous), 146356/179200 blocks` (saída 0).
   - `debugfs`: `/usr/bin/sudo` com `Mode: 04755`, `/home/r8s/.ssh/authorized_keys` com `Mode: 0600`, `User: 1000`, `Group: 1000`, `Size: 91`, `/usr/lib/modules/6.12.0-rc5-next-20241104-r8s/modules.dep` (`0:0`), `/usr/lib/modules/6.12.0-rc5-next-20241104-r8s/kernel/drivers/gpu/drm/panfrost/panfrost.ko` (`0:0`), `/etc/ssh/sshd_config.d/10-r8s.conf` (`0:0`), `/etc/modules-load.d/r8s-softdog.conf` (`0:0`), `/etc/systemd/system.conf.d/10-r8s-watchdog.conf` (`0:0`), `/etc/sysctl.d/90-r8s-recovery.conf` (`0:0`) e `/etc/systemd/system/r8s-pstore-archive.service` (`0:0`) presentes.
   - `out/rootfs/arch-base-packages.txt`: 160 pacotes AArch64; apenas `linux-api-headers 7.3-1` casa com `^linux` (nenhum pacote de kernel genérico).
3. **Logs de build em `logs/`**: `m1-build-lk3rd.log`, `m1-build-kernel.log`, `m1-rootfs-slim.log`, `m1-rootfs-mini.log`, `m1-build-package.log`, `m1-arch-rootfs.log`.
