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

## Fontes públicas encontradas (19/11/2026)

- **Scion-Project `drivers/modem/hakios.shannon.c`** ([PR #301](https://github.com/Scion-Project/scion-kernel/pull/301)), arquivo **MIT-0**: bring-up do Shannon *integrado* do Galaxy S9 (Exynos 9810, ss360ap) sem Android.
  - Boot por memória compartilhada mais SMC `0x82000700` na EL3. **Não é o nosso caminho de boot**: o S5123 usa SPI e PCIe.
  - Handshake do bootloader no canal 215: `0x900D`→`0xA00D` e `0x9F00`→`0xAF00`, em quadros `{0xfc, 215, 8, 0, word}`.
  - Depois do boot: `INIT_START`, tabela de anéis, `PIF_INIT_DONE`, `PHONE_START` (mensagem: bit 7 válido, bit 6 comando, bits 5:0 com 1/2/8/0xD/7/9).
  - Quadro SIPC5: `0xF8` (bit 2 = padding), canal e comprimento de 16 bits com o cabeçalho incluído.
  - SIM e registro na rede.
  - PDP pelo IPC Samsung, grupo `0x0D` (número 1 "set"; resposta geral `0x8000`; o CP devolve `0x0D/0x09` e `0x0D/0x10`).
  - Dados: canal 10 = contexto 1, interface `pdp_ip0`.
  - **Serve de referência para as etapas de IPC, rádio e dados.**
- **tonyg, `qnd_cbd.py`/`qnd_ril.py`** ([gist](https://gist.github.com/tonyg/4ea14f4dfe414422c0648c6e0a8bcb5d)), Galaxy S7, sem licença declarada, então só como referência de fatos.
  - Boot pelas ioctls do kernel Samsung (memória compartilhada) e handshake `0x900d`/`0x9f00` em `umts_boot0`.
  - Cabeçalho IPC de 7 bytes `len16, msg_seq, ack_seq, main_cmd, sub_cmd, cmd_type`.
- Contexto: [ARM Ninja, S6 modem](http://arm.ninja/2016/03/04/reverse-engineering-samsung-s6-modem/), [Comsecuris, Breaking Band](https://comsecuris.com/slides/recon2016-breaking_band.pdf), [Black Hat 2020, FirmWire](https://i.blackhat.com/USA-20/Wednesday/us-20-Hernandez-Emulating-Samsungs-Baseband-For-Security-Testing.pdf).

## Escuta do bootloader do S5123 (`packaging/modem/cp-boot-listen.py`, kernel #17)

IPC preparado como `init_legacy_link()`/`link_start_normal_boot()` (magic `BOOT`, `access=1`, filas zeradas), mais BOOT por SPI, link PCIe e doorbell `pcie_link_ack` (14). **O CP não escreveu nada em 6 s**: filas RX vazias e `cp2ap_msg` intacto. Coerente com o STD UDL, em que o AP fala primeiro (`std_udl_stage_start`). Para conhecer a primeira mensagem é preciso o comportamento do `cbd`.

No `cbd`, as referências às strings ficam em `.rodata` com deslocamento entre arquivo e memória: `std_udl_req_resp` é referenciado em `0x16a8c` por `adrp 0x7000` + `#0xe40`. A análise estática é viável, mas longa.
