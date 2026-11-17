# M0 — Telemetria de Hardware Observada (SM-G780F / r8s)

Coletado em **17/11/2026** via `adb shell` (somente leitura, `uid=0` / `u:r:su:s0`) com o aparelho em **Lineage Recovery** (`LineageOS 24.0-20261116-NIGHTLY-r8s`, kernel `4.19.325-cip126-st10-g97369af7bbd6`). Identificadores pessoais (`serialno`, `ap_serial`, `em.did`, IMEI, MACs) foram removidos.

> [!IMPORTANT]
> **Descobertas críticas para M1/M2:**
> 1. **RAM de 6 GB (não 8 GB):** este aparelho reporta `androidboot.ddr_size=6`, `dram_info=01,07,00,6G` e `MemTotal: 5589576 kB` (~5,33 GiB). O DTS do port (`sources/port/kernel/patches/0003-*` e `0024-*`) declara a variante de **8 GB** (`<0x8 0x80000000 0x1 0x7ec00000>`). Bootar o DTB de 8 GB neste aparelho de 6 GB pode mapear RAM inexistente e travar/corromper o sistema — é obrigatório confirmar os nós `/sys/firmware/devicetree/base/memory*` deste aparelho e adaptar o `memory@80000000` antes de M1/M2.
> 2. **Touchscreen em `i2c-5/5-0020` (`108d0000.hsi2c`):** no kernel LineageOS aparece como `sec_touchscreen` em `108d0000.hsi2c/i2c-5/5-0020` (`0..1079` x `0..2399`, 10 contatos). O endereço `0x20` em `hsi2c@108D0000` corresponde à variante **Zinitix ZT7650** (e não ao alterno STM FTS em `0x49`).
> 3. **Tamanho real de `boot` (`sda13`):** **61.865.984 bytes (~59,0 MiB)** — menor que o teto de 64 MiB (`67.108.864 B`) assumido para `r8s-ram.img`; `recovery` (`sda14`) tem **69.009.408 bytes (~65,8 MiB)**.

## 1. Sistema e Devicetree Base

- **Uname:** `Linux localhost 4.19.325-cip126-st10-g97369af7bbd6 #1 SMP PREEMPT Mon Nov 16 03:40:01 UTC 2026 aarch64`
- **Propriedades (`getprop`):**
  - `ro.product.model`: `SM-G780F`
  - `ro.product.device`: `r8s`
  - `ro.product.board` / `ro.hardware`: `exynos990`
  - `ro.board.platform`: `universal990`
  - `ro.bootloader`: `G780FXXSOFYJ2`
  - `ro.boot.warranty_bit`: `1`
  - `ro.build.version.release`: `17`
  - `ro.lineage.version`: `24.0-20261116-NIGHTLY-r8s`
- **Devicetree (`/sys/firmware/devicetree/base/`):**
  - `model`: `Samsung R8S EUR OPEN 05 based on EXYNOS990`
  - `compatible`: `samsung,armv8`, `samsung,exynos990`
  - `chosen/`: `bootargs` (2652 B), `bootargs_ext` (68 B), `linux,initrd-start` (`0x88080000` em BE), `linux,initrd-end` (`0x8917d611` em BE).
- **Montagens ativas no Recovery (`mount`):**
  - `/` (`rootfs`), `/dev`, `/proc`, `/sys`, `/tmp`, `/config`, `/sys/fs/pstore`, `/dev/usb-ffs/adb`, `/dev/usb-ffs/fastboot`, e `/dev/block/sda2` em `/efs` (ext4).
  - `/vendor` e `/system_root` **não** estavam montados.

## 2. Linha de Comando do Kernel (`/proc/cmdline` sanitizado)

Parâmetros relevantes observados (identificadores removidos):

```text
androidboot.boot_devices=13100000.ufs root=/dev/ram0 androidboot.hardware=exynos990
firmware_class.path=/vendor/firmware corememsize=8G
sec_debug.lpddr4_size=6.0 sec_debug.dram_info=01,07,00,6G androidboot.dram_info=01,07,00,6G androidboot.ddr_size=6
s3cfb.bootloaderfb=0xf1000000 lcdtype=8388674 mcd-panel.boot_panel_id=8388674
pmic_info=43 ccic_info=1 wireless_ic=0x20014440
androidboot.carrierid=ZTO sales_code=ZVV androidboot.bootloader=G780FXXSOFYJ2
androidboot.revision=5 androidboot.warranty_bit=1 androidboot.rp=24 androidboot.dtbo_idx=2
androidboot.em.model=SM-G780F androidboot.verifiedbootstate=orange
androidboot.ap_serial=<REDACTED> androidboot.serialno=<REDACTED> androidboot.em.did=<REDACTED>
```

Nota: `bootargs_ext` contém `root=/dev/ram0 androidboot.boot_devices=13100000.ufs sec_debug.cp=0`.

## 3. CPU e Memória

- **`/proc/cpuinfo` (8 núcleos ARMv8):**
  - `processor 0..3`: `CPU implementer 0x41`, `CPU variant 0x2`, `CPU part 0xd05`, `CPU revision 0` (4x ARM Cortex-A55)
  - `processor 4..5`: `CPU implementer 0x41`, `CPU variant 0x3`, `CPU part 0xd0b`, `CPU revision 1` (2x ARM Cortex-A76)
  - `processor 6..7`: `CPU implementer 0x53`, `CPU variant 0x1`, `CPU part 0x004`, `CPU revision 0` (2x Samsung M5)
  - `Features`: `fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp`
  - `Hardware`: `Samsung R8S EUR OPEN 05 based on EXYNOS990`
- **`/proc/meminfo`:**
  - `MemTotal`: `5589576 kB` (~5,33 GiB utilizáveis; variante de 6 GB)
  - `MemFree`: `4902456 kB`, `MemAvailable`: `4915968 kB`

## 4. Tabela de Partições UFS (`/dev/block/by-name/*` + `/sys/class/block/*/size`)

Dispositivos UFS (`13100000.ufs`): `sda` (127.934.660.608 B / 119,15 GiB), `sdb` (4.194.304 B), `sdc` (4.194.304 B), `sdd` (8.388.608 B), `sde` (16.777.216 B). Tamanhos calculados em 64 bits no host (`setores × 512`, evitando overflow de 32 bits no `sh` do recovery).

| Nome (`by-name`) | Bloco | Setores (512 B) | Tamanho (bytes) | Observação |
| --- | --- | ---: | ---: | --- |
| `efs` | `sda1` | 40960 | 20971520 | 20 MiB |
| `sec_efs` | `sda2` | 40960 | 20971520 | 20 MiB (montado em `/efs` no recovery) |
| `param` | `sda3` | 16384 | 8388608 | 8 MiB |
| `up_param` | `sda4` | 16384 | 8388608 | 8 MiB |
| `bota` | `sda5` | 81920 | 41943040 | 40 MiB |
| `keystorage` | `sda6` | 1024 | 524288 | 512 KiB |
| `steady` | `sda7` | 8192 | 4194304 | 4 MiB |
| `harx` | `sda8` | 6144 | 3145728 | 3 MiB |
| `uh` | `sda9` | 4096 | 2097152 | 2 MiB |
| `uhcfg` | `sda10` | 8192 | 4194304 | 4 MiB |
| `dtbo` | `sda11` | 16384 | 8388608 | 8 MiB |
| `blcmd` | `sda12` | 128 | 65536 | 64 KiB |
| `boot` | `sda13` | 120832 | 61865984 | **59,0 MiB** (teto real para `boot.img`) |
| `recovery` | `sda14` | 134784 | 69009408 | **65,8 MiB** |
| `radio` | `sda15` | 143360 | 73400320 | 70 MiB |
| `cp_debug` | `sda16` | 10240 | 5242880 | 5 MiB |
| `nad_refer` | `sda17` | 2048 | 1048576 | 1 MiB |
| `persistent` | `sda18` | 1024 | 524288 | 512 KiB |
| `misc` | `sda19` | 2048 | 1048576 | 1 MiB |
| `keyrefuge` | `sda20` | 32768 | 16777216 | 16 MiB |
| `keydata` | `sda21` | 32768 | 16777216 | 16 MiB |
| `dqmdbg` | `sda22` | 32768 | 16777216 | 16 MiB |
| `vbmeta` | `sda23` | 128 | 65536 | 64 KiB |
| `vbmeta_samsung` | `sda24` | 128 | 65536 | 64 KiB |
| `metadata` | `sda25` | 65536 | 33554432 | 32 MiB |
| `super` | `sda26` | 18432000 | 9437184000 | ~8,79 GiB |
| `prism` | `sda27` | 2048000 | 1048576000 | 1000 MiB |
| `optics` | `sda28` | 61440 | 31457280 | 30 MiB |
| `cache` | `sda29` | 1228800 | 629145600 | 600 MiB |
| `omr` | `sda30` | 102400 | 52428800 | 50 MiB |
| `spu` | `sda31` | 102400 | 52428800 | 50 MiB |
| `userdata` | `sda32` | 227057664 | 116253523968 | ~108,27 GiB |
| `cpefs` | `sdd1` | 12288 | 6291456 | 6 MiB |

(`sdb`, `sdc`, `sdd`, `sde` também aparecem em `/dev/block/by-name/` apontando para os discos UFS inteiros correspondentes.)

## 5. Entrada e Touch (`/sys/class/input/event*` + `getevent -lp`)

| Evento | Nome | Caminho / `phys` | Detalhes observados |
| --- | --- | --- | --- |
| `event0` | `meta_event` | — | `REL_HWHEEL`, `REL_DIAL` |
| `event1` | `gpio_keys` | `gpio-keys/input0` (`bustype=0019`) | `KEY_VOLUMEDOWN`, `KEY_VOLUMEUP`, `KEY_POWER` |
| `event2` | `sec_touchscreen` | `sec_touchscreen/input1`, `108d0000.hsi2c/i2c-5/5-0020` (`bustype=0018`) | `INPUT_PROP_DIRECT`; `KEY_WAKEUP`, `BTN_TOUCH`; `ABS_X`/`ABS_MT_POSITION_X` `0..1079`, `ABS_Y`/`ABS_MT_POSITION_Y` `0..2399`, `ABS_MT_SLOT` `0..9` (10 dedos), `ABS_MT_TOUCH_MAJOR`/`MINOR`/`WIDTH_MAJOR` `0..255`, `LED_MISC` (`input2::misc`) |
| `event3` | `sec_touchproximity` | `sec_touchproximity/input1` (`bustype=0018`) | `INPUT_PROP_DIRECT` |
| `event4` | `grip_sensor` | `bustype=0018` | `REL_X`, `REL_MISC` |
| `event5` | `grip_notifier` | `bustype=0018` | `REL_X` |
| `event6` | `ssp_context` | `bustype=0000` | `REL_RX`, `REL_RY`, `REL_RZ` |
| `event7` | `als_rear` | `bustype=0018` | `REL_X/Y/Z/RX/RY/RZ/MISC`, `ABS_X/Y/Z` |
| `event8` | `hall` | `hall` | `SW_LID` |
| `event9` | `certify_hall` | `certify_hall` | `SW_MACHINE_COVER` |

## 6. Display, Framebuffer e Backlight

- `/sys/class/drm/`: vazio no kernel LineageOS 4.19 (usa Exynos DECON proprietário, não DRM/KMS).
- `/sys/class/graphics/`:
  - `fb0` → `19050000.decon_f`: `modes: U:1080x2400p-0`, `bits_per_pixel: 32`, `stride: 4320`, `virtual_size: 1080,4800`, `pan: 0,2400`. Coerente com `framebuffer@f1000000` (`1080 * 4 = 4320` bytes/linha, buffer duplo).
  - `fb1` → `19060000.decon_s`
  - `fb2` → `19070000.decon_t`
- `/sys/class/backlight/panel` (`panel_drv@0/backlight/panel`): `brightness=121`, `max_brightness=486`.
- `/sys/class/lcd/panel` (`panel_drv@0/lcd/panel`): `lcd_type=SDC_800042` (`mcd-panel.boot_panel_id=8388674` = `0x800042`), expõe `vrr`, `vrr_lfd`, `dynamic_freq`, `display_mode`, `fingerprint`, `mdnie`, `temperature`, `lux`, `alpm`, `partial_disp`, etc.

## 7. Energia (`/sys/class/power_supply/*` — coleta parcial)

- `ac`: `type=Mains`, `online=0`, `current_max=475000`, `voltage_max=5000000`, `temp=335`
- `battery` (lido até `charge_now`):
  - `capacity=100`, `batt_read_raw_soc=10000`
  - `voltage_now=4362000`, `batt_inbat_voltage=4329`, `batt_vfocv=4327`
  - `charge_full=2927000`, `charge_full_design=4500000`, `charge_counter=2927000`, `batt_capacity_max=1000`
  - `batt_temp=334` (33,4 °C), `batt_current_ua_now=11250`, `batt_current_ua_avg=625`

> [!WARNING]
> Ao listar/ler atributos de `/sys/class/power_supply/battery/*` com curinga, a leitura de um atributo vendor de `sec_battery` imediatamente após `charge_now` causou desconexão USB / reset do kernel no recovery (06:38:31), reiniciando o aparelho. Em sessões futuras, **nunca** ler `/sys/class/power_supply/battery/*` em lote com curinga; ler apenas `ls /sys/class/power_supply/` e atributos padrão específicos.

## 8. Itens Pendentes para Próxima Sessão ADB Root

Por conta do reset em `power_supply/battery/*`, ficaram pendentes nesta coleta:

- Listagem completa de `/sys/class/power_supply/` (ex.: `max77705-charger`, `max77705-fuelgauge`, `otg`, `wireless`) e apenas atributos padrão seguros.
- `/sys/firmware/devicetree/base/memory*` (regiões exatas da variante de **6 GB** para corrigir `exynos990-r8s.dts` no port).
- `/sys/class/thermal/thermal_zone*` (tipos, temperaturas e trip points).
- `/sys/bus/i2c/devices/*`, `/sys/bus/spi/devices/*`, `/sys/class/lcd/panel/vrr` e `display_mode`.
- Resumo de `dmesg` (panel, touch, UFS, PMIC, USB, Wi-Fi/PCIe, áudio/ABOX, sensores, câmera) e eventual `/sys/fs/pstore` após o reset.
