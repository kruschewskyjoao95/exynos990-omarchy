# S5123: como o LineageOS carrega o firmware principal (marco 4)

Levantamento de 19/11/2026. Fontes:
- **[código]** kernel LineageOS `97369af7`, `drivers/soc/samsung/cpif/`;
- **[vendor]** partição `vendor` deste aparelho, lida da `super` (`sda26`, ext4 em +5602 MiB, 1380 MiB), só leitura;
- **[strings]** saída de `strings` do binário `cbd`.

Nenhum código do binário foi copiado. Ele fica fora do git.

## Linha de comando ([vendor] `etc/init/init.baseband.rc:19`)

```
service cpboot-daemon /vendor/bin/cbd -d -t s5100 -P by-name/radio -bs -me -B umts_boot0 -D umts_ramdump0 -n /mnt/vendor/efs
```

`cbd`: 156.944 B, ELF aarch64 Android 30, SHA-256 `c94168597aa426b245f4bf4e1e89911768318ea95f41c22662058ec39961b753`.

## Divisão kernel × `cbd` ([código])

- `IOCTL_LOAD_CP_IMAGE` → `cpboot_spi_load_cp_image()`: um `spi_sync` cru do BOOT. Reproduzido no marco 2.
- `IOCTL_START_CP_BOOTLOADER(NORMAL)` → `start_normal_boot()` → `link_start_normal_boot()` (zera filas e grava o magic de boot), `check_cp_status()` (espera `CP2AP_WAKEUP`) e `register_pcie()` → `s5100_poweron_pcie()` (`AP2CP_WAKEUP=1`, RC on, S2MPU `hsi2` RW para o `cp_shmem`, doorbell `int_pcie_link_ack`). A parte de PCIe foi reproduzida no marco 3.
- **O firmware principal não passa por ioctl.** O `cbd` escreve as mensagens do protocolo de boot em `/dev/umts_boot0` (`bootdump_write()`, quadros SIPC5 na fila legacy da memória compartilhada, avisando o CP por doorbell PCIe).
- `IOCTL_REQ_SECURITY` → `security_req` só existe para `LINKDEV_SHMEM` (`link_device.c:3727`). No S5123 (`LINKDEV_PCIE`) **não há SMC de verificação no AP**. As mensagens "security check fail for TOC/VSS" e "secure err: Invalid Main image" [strings] indicam verificação feita pelo próprio CP ou relatada por ele.
- `IOCTL_COMPLETE_NORMAL_BOOTUP` → `complete_normal_boot()`: espera `init_cmpl`, liga o L1.2 e as IRQs `phone_active`/`cp2ap_wakeup`, e passa a `STATE_ONLINE`.

## Protocolo de boot "STD UDL" ([strings], nomes de funções e mensagens)

- Sequência: `std_boot_load_cp_bootloader` (BOOT pelo SPI, "BOOT link SPI"), depois "main PCIE link" → `std_boot_load_cp_image` / `std_boot_dload`.
- Para cada estágio da TOC: `std_udl_stage_start` (falha reportada como "START fail (req:0x%X exp:0x%X)"), `std_dl_send_bin`, `std_dl_send_crc` e `std_udl_stage_done` ("DONE fail (req:0x%X exp:0x%X)").
- Funções auxiliares: `std_udl_req_resp`, `std_ul_rx_frame` ("[step %d] cmd 0x%X != exp 0x%X"), `std_ul_recv_info`, `std_ul_recv_data` e `std_udl_poll`.
- Log de cada estágio: "stage=%u, name:%s b_off=0x%08x, m_offset=0x%08x b_size=0x%08x", com campos que batem com a TOC do `radio` (`checks/modem-s5123.md`).
- NV: `%s/nv_data.bin` dentro de `-n /mnt/vendor/efs`. Se não existir, usa `create_empty_nv`.
- Fim: "Boot up process done!!!", propriedade `vendor.cbd.boot_done`, arquivo `cp_boot_done_%s`.

## O que falta para um carregador aberto

1. **Transporte no kernel**, portado do `cpif`: a região `cp_shmem` (IPC de 8 MiB, MSI), a fila legacy com quadros SIPC5, o doorbell PCIe e o nó `umts_boot0`. Também a liberação da S2MPU `hsi2` para o CP ler e escrever na RAM do AP, por HVC.
2. **Formato das mensagens STD UDL:** códigos de comando, `req`/`exp` de cada estágio, layout de cabeçalho e CRC. Exige desmontar o `cbd` só para interoperar, ou achar descrição pública. O ShannonRE/ShannonBaseband cobre o firmware do CP, não este protocolo, até onde foi visto.
3. Um carregador aberto que leia a TOC do `radio` e o `nv_data.bin` do `efs` e percorra os estágios.
