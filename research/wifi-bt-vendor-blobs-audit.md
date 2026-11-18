# Auditoria offline dos firmwares Wi-Fi/BT em `blobs/r8s-device/vendor/`

Data: 2026-11-17. Agente: `[gemini]`. Escopo: leitura e verificação cruzada de `blobs/r8s-device/vendor/` contra `blobs/firmware/`, `manifests/bluetooth-firmware.sha256`, `out/boot/initramfs-slim.cpio.gz` e `out/rootfs/ufs-root.img` (conjunto **baseline**). Nenhum blob proprietário foi copiado para caminhos rastreados pelo Git; nenhum teste foi executado no aparelho.

Complementa [`research/wifi-bt-firmware.md`](wifi-bt-firmware.md).

## 1. Inventário observado em `blobs/r8s-device/vendor/root/`

Origem registrada em `blobs/r8s-device/vendor/LEIAME.txt`: vendor do LineageOS 24.0-20261116 (`r8s`, `lineage-vendor.img` EROFS de `242888704` B).

### Wi-Fi (QCA6390)

| Arquivo em `blobs/r8s-device/vendor/root/` | Tamanho (bytes) | SHA-256 observado | Uso / observação |
|---|---|---|---|
| `firmware/qca6390/amss20.bin` | `3667648` | `e09d8e3c66567089f65ba59328f6c376b7915ad022b9e3f99362a3cc5da664f4` | Ramo Android `qcacld`/`cnss` (`HSTE … LITE_R`), distinto do `amss.bin` `TO_X86` usado pelo `ath11k` |
| `firmware/qca6390/m3.bin` | `266684` | `1c1b0e57599ab4944beabf77b18b9924947044790117b3aead989a1804956f71` | Mesmo tamanho do `m3.bin` do `linux-firmware` (`266684` B), mas SHA diferente (`1921d25e…` no `blobs/firmware/`) |
| `firmware/qca6390/bdwlan.elf` | `57836` | `9fe8b78f8d8316938877b330d46c753cbb31dfb3de670c2d9428bf5d824a64f7` | BDF Samsung principal (base do `board-2.r8s.bin` de `57964` B) |
| `firmware/qca6390/bdwlan.elf1` | `57836` | `d067b17727d851bac3181e66900d9422f234a50632860ad7269af6da75ab8a62` | Variante antena única 1 |
| `firmware/qca6390/bdwlan.elf2` | `57836` | `7e84e98fe295206454203f8a13b6b7fafe44bae7ee29a101b662af3f4e2fe6f` | Variante antena única 2 |
| `firmware/qca6390/regdb.bin` | `19348` | `8749e6c5e98993419224eb7d8149c86b9f4dae949a8cbde7e84d2b3089812721` | Não usado pelo `ath11k` em QCA6390 (`supports_regdb = false`) |
| `firmware/wlan/qcom_cfg.ini` | `12077` | `af06bd9106d5b06199b9cef5a34f4a0b113da6fbca7cca1feae52cfb372caf64` | Configuração `qcacld` (não se aplica ao `ath11k`) |
| `etc/wifi/indoorchannel.info` | `14943` | `4dae7c43a6c7f5a34f4d67307f6ba1bf322debe3e5252ad8b237dca8edba48d72` | Tabela de canais Android |
| `etc/wifi/p2p_supplicant_overlay.conf` | `373` | `7ba36c0438e7859366ba6b2a35ddee3531d8b2908f4154ab7ba6156e68` | Overlay `wpa_supplicant` Android |
| `etc/wifi/wpa_supplicant.conf` | `197` | `cf3aece779df4d7780005a626501273e97ae5de3bd764e81369c8602d1137be9` | Config `wpa_supplicant` Android |
| `etc/wifi/wpa_supplicant_overlay.conf` | `60` | `4ae621ddc7999e336a0c991e4693d27f728caa8b5f64421ed2462286fa49d83e` | Overlay `wpa_supplicant` Android |

### Bluetooth (QCA6390)

| Arquivo em `blobs/r8s-device/vendor/root/` | Tamanho (bytes) | SHA-256 observado | Correspondência em `manifests/bluetooth-firmware.sha256` |
|---|---|---|---|
| `firmware/htbtfw20.tlv` | `211704` | `8427ba9487d322c5e3e618b75ff51c0103308d425e6eb21996f0493b0969dcbb` | **Idêntico** ao hash fixado |
| `firmware/htnv20.bin` | `6037` | `6f66ff12e95c7679f4894fffb0db77c165053d02356d81471474fb2d525fc15c` | **Idêntico** ao hash fixado |

## 2. Achados em scripts `.rc` do vendor

Em `blobs/r8s-device/vendor/root/etc/init/`:
- `init.exynos990.rc:853-869`:
  - UART do Bluetooth no Android é `/dev/ttySAC1` (`chown bluetooth bluetooth /dev/ttySAC1`), compatível com o nó UART1 (`10480000.serial`) investigado para RTS em `0106`.
  - Endereço MAC do Bluetooth no vendor vem da partição EFS: `ro.bt.bdaddr_path "/mnt/vendor/efs/bluetooth/bt_addr"`. No Arch/mainline (sem EFS montado), o endereço precisa vir do DT (`local-bd-address`), NVM ou `btmgmt public-addr` caso o chip não tenha BD_ADDR em OTP.
  - Controle de alimentação/rfkill: `/dev/btpower` e `/sys/class/rfkill/rfkill0/{state,type}`.
- `wifi.rc:51,65` e `wifi_qcom_ap_exynos.rc:43-52`:
  - `macloader` lê MAC/configuração antes do `boot_wlan`; recuperação de falha usa `/sys/devices/platform/qcom,cnss-qca6390/recovery`.

## 3. Estado nos artefatos atuais do conjunto baseline (`out/`)

Inspeção offline em `out/boot/initramfs-slim.cpio.gz` (`gzip -dc | cpio -tv`) e `out/rootfs/ufs-root.img` (`debugfs -R 'ls -l ...'`):

1. **`out/boot/initramfs-slim.cpio.gz` (teste em RAM):**
   - Contém os módulos `ath11k.ko`, `ath11k_pci.ko` e `btqca.ko` (`6.12.0-rc5-next-20241104-r8s`).
   - Contém `usr/lib/firmware/ath11k/QCA6390/hw2.0/{amss.bin,m3.bin,board-2.bin}` (versão `linux-firmware` / `blobs/firmware/`, tamanhos `3628672`, `266684`, `231980` B).
   - **Não** contém `board-2.r8s.bin` nem `qca/{htbtfw20.tlv,htnv20.bin}` (esperado para o slim focado em boot/console/tela/toque/Wi-Fi).

2. **`out/rootfs/ufs-root.img` (rootfs Arch ARM mínimo):**
   - `/usr/lib/firmware/ath11k/QCA6390/hw2.0/` contém: `Notice.txt` (`189707` B), `amss.bin` (`3628672` B), `m3.bin` (`266684` B), `board-2.bin` (`231980` B, padrão do port) e `board-2.r8s.bin` (`57964` B, BDF Samsung de `bdwlan.elf`).
   - `/usr/lib/firmware/qca/` contém: `htbtfw20.tlv` (`211704` B) e `htnv20.bin` (`6037` B), correspondendo aos tamanhos e hashes do vendor auditado acima.
   - Como o kernel baseline atual (`cd727178…`) usa `CONFIG_EXTRA_FIRMWARE=""`, o `ath11k_pci` (`=m`) passará a ler o firmware do `/usr/lib/firmware` (sem bloqueio por firmware embutido no `Image`), permitindo testar `board-2.bin` vs `board-2.r8s.bin` no aparelho sem recompilar o kernel.
