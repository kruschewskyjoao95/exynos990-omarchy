# Modem Shannon S5123: bring-up no Arch

Testado neste aparelho em 19/11/2026, kernel #12, por SSH. A referência é o LineageOS `97369af7`: `drivers/soc/samsung/cpif/modem_ctrl_s5100.c` e `exynos9830-universal9830-cp-s5123-sipc.dtsi`, incluído pelo `exynos990-r8s_eur_open_0{0,2,5}.dts` sem sobrescrever os GPIOs. A pesquisa base fica em `roadmap/10-modem-r8s.md`.

## Marco 1: energia do CP por GPIO (feito)

Pinos usados, todos livres no Arch e acessados pelo `libgpiod` 2.2.1, instalado no aparelho:

| Sinal | Pino | gpiochip |
|---|---|---|
| `cp_pwr_on` | gpm20-0 | 41 |
| `nreset_n` | gpm9-0 | 30 |
| `pda_active` | gpm25-0 | 46 |
| `dump_noti` | gpp8-6 | 9, linha 6 |
| `cp_ps_hold` | gpm31-0 | 52 |
| `cp2ap_wakeup` | gpm30-0 | 51 |
| `phone_active` | gpm28-0 | 49 |

Sequência de `power_on_cp()`: `pda_active=1`, `dump_noti=0`, `nreset=0`, 50 ms, `cp_pwr_on=1`, 50 ms, `nreset=1`. Para desligar, `power_off_cp()`: `nreset=0` e depois `cp_pwr_on=0`.

| Momento | ps_hold | cp2ap_wakeup | phone_active |
|---|---|---|---|
| CP desligado | 1 | 1 | 0 |
| CP ligado (0–4 s) | **0** | 1 | 0 |
| CP desligado de novo | 1 | 1 | 0 |

O `ps_hold` acompanha a energia do CP, então **o S5123 é alimentado e reage aos GPIOs** sem driver novo. Ressalva: as entradas estão sem o pull que o LineageOS configura (`ps_hold` com pull-down, os demais sem pull e com função EINT 0xF), então a polaridade e os níveis em repouso não estão confirmados. O `cp2ap_wakeup` não muda, o que é esperado antes do boot: `check_cp_status()` só o espera depois do boot por SPI.

## Firmware: TOC da partição `radio` (`/dev/sda15`, 70 MiB, só leitura)

| Seção | Offset | Endereço no CP | Tamanho | CRC |
|---|---|---|---|---|
| TOC | 0x0 | 0x40008000 | 0x320 | — |
| BOOT | 0x320 | 0x40000000 | 0xfb90 | 0xfbfde917 |
| MAIN | 0xfec0 | 0x40010000 | 0x2ee7360 | 0xb6ba51ad |
| APM | 0x2ef7220 | 0x10000 | 0x7420 | 0xcaffed19 |
| VSS | 0x2efe640 | 0x4f900000 | 0x49aaa0 | 0x457c40ed |
| NV | — | 0x4b500000 | 0x100000 | — |
| OFFSET | 0x80000 | — | 0x80000 | — |
| INFO | 0x33990e0 | 0x40009000 | 0x180 | 0x84b6ab26 |

## Marco 2: boot por SPI (feito; kernel #13, 0140 `cc4e96e8…`)

- **DT (0140):**
  - USI16 em modo SPI: `sysreg_peric1+0x1048`, que passou a ler `0x2`.
  - Controlador `exynos850-spi` em `0x10960000`, IRQ 434. Sobe como `spi0.0`.
  - `spidev` no CS0 a 2,15 MHz, com os grupos de pinos `spi16_bus`/`spi16_cs_func` que já existiam.
- **Clock:** o USI SPI não tem prescaler e divide o ipclk por 4. Como o CMU_PERIC1 não é modelado, o roteiro seleciona o OSC de 26 MHz (`0x10700690` bit 4 = 0) e `DIVRATIO=2` (`0x10701820`): 8,67 MHz no ipclk e 2,17 MHz no SCLK. Antes estava em 400 MHz/1, o que daria 100 MHz.
- **Roteiro:** `packaging/modem/cp-spiboot.sh`. Carrega o `spidev` com `bufsiz=65536`, extrai o BOOT (`0x320`, 64.400 B) do `radio`, liga o CP sem mexer no gpp8-6 (que agora é pino do SPI), envia o BOOT num único `spi_sync`, observa e desliga.
- **Leitura com `gpioget -b pull-down`:** com o CP desligado as entradas flutuam e seguem o bias.

| Ensaio | ps_hold | cp2ap_wakeup |
|---|---|---|
| CP desligado | 0 | 0 |
| CP ligado, sem SPI (0–4 s) | 0 | 0 |
| CP ligado, **~200 ms após o BOOT por SPI** | **1** | **1** |

O bootloader do CP roda com o firmware enviado pelo Arch, e o `cp2ap_wakeup=1` é a condição de `check_cp_status()` para `register_pcie()`.

## Marco 3: PCIe canal 1 (feito, protótipo em espaço de usuário, kernel #13)

O controlador do modem é o **GEN4_1 do HSI2** (`pcie@13D20000`), diferente do GEN2/HSI1 do Wi-Fi. O protótipo `packaging/modem/cp-pcie-link.py` reproduz pelo `/dev/mem` a sequência `s5100_poweron_pcie()`/`exynos_pcie_rc_poweron()`/`establish_link()` e a calibração `chip_ver=1` de `pcie-exynos9830-rc-cal.c`.

Duas armadilhas, cada uma achada no aparelho:
1. **Isolação do PHY antes de tudo.** ELBI, PHY, PCS e DBI ficam atrás do bit 0 do PMU `0x15860720`. Qualquer acesso antes de liberá-lo trava o SoC (travamento seco e reboot pelo watchdog, reproduzido duas vezes). Com o bit em 1, o ELBI responde (`LTSSM=0xfb7f00`, `SOFT_RESET=0xf`). É a mesma ordem do caminho Wi-Fi do port (`0x718` primeiro).
2. **`AP2CP_WAKEUP` (gpg1-3, `gpiochip12` linha 3) = 1, depois 5 ms**, antes do power-on do RC, como `s5100_poweron_pcie()`. Sem ele, o LTSSM fica em `DETECT_QUIET`↔`DETECT_ACT`: o endpoint não apresenta terminação.

Resultado com o CP em boot por SPI (`ps_hold=cp2ap_wakeup=1`):

| Item | Valor |
|---|---|
| LTSSM | `POLL_ACTIVE` → `POLL_CONFIG` → `CFG_IDLE` → **L0** em < 0,1 ms |
| Link (DBI `0x80`) | `0x30210000`: **Gen1 x2** (`num-lanes = <2>` do LineageOS) |
| RC (DBI) | `144d:a5a5`, `header_type=1` |
| **Endpoint (barramento 1)** | **`144d:a5a5`**, class/rev `0x00000001`, **`header_type=0`**, BAR0 `0x00000004` (memória de 64 bits) |

Para ler o barramento 1: barramento secundário do RC = 1 (DBI `0x18 = 0x00010100`) e iATU região 0 (DBI `+0x300000`) como CFG0, com a janela `config` em `0x14FFE000`. É o `exynos_pcie_rc_prog_viewport_cfg0()`. O `s51xx_pcie` do LineageOS aceita qualquer `PCI_VENDOR_ID_SAMSUNG`.

Falta levar isso para o kernel: um caminho GEN4 no `pci-exynos.c`, ou driver próprio, mais o nó `pcie@13D20000` com a ordem PMU → AP2CP_WAKEUP → PHY.

## Marco 4a, passo 1: driver de kernel do PCIe GEN4_1 (feito; kernel #15, 0141 `fbcdb5ad…`)

- **Driver novo `drivers/pci/controller/dwc/pcie-exynos990-gen4.c`** (glue DesignWare, `CONFIG_PCIE_EXYNOS990_GEN4=y`), mais o nó `pcie_modem: pcie@13d20000` no `exynos990-r8s.dts`: domínio PCI 1, 2 lanes, PERST gpf3-1, `pcie2_clkreq`/`pcie2_perst`, PMU por `samsung,pmu`.
- **No boot:** com o CP desligado, aparece "Phy link never came up", e o host registra o barramento `0001` só com o root port `144d:a5a5`. Sem WARN, porque um fixup põe `no_msi` nos dispositivos deste host: ainda não há controlador MSI.
- **Sob demanda:** `cp-spiboot.sh` (com `KEEP_CP_ON=1`), depois `AP2CP_WAKEUP=1` e `echo 1 > /sys/bus/platform/devices/13d20000.pcie/relink`. O link treina e o `lspci` mostra:

```
0001:00:00.0 PCI bridge [0604]: Samsung Electronics Co Ltd Device [144d:a5a5] (rev 01)
0001:01:00.0 Non-VGA unclassified device [0000]: Samsung Electronics Co Ltd Device [144d:a5a5] (rev 01)
	Region 0: Memory at <ignored> (64-bit, non-prefetchable) [size=1M]
	LnkSta: Speed 16GT/s, Width x2
```

- `echo 0 > relink` remove o endpoint. O Wi-Fi (domínio 0000) não foi afetado.
- **Pendências:**
  - BAR0 sai como `<ignored>`. **Não é bug:** o endpoint tem classe `0x000000`, e o PCI core não atribui recursos a dispositivos sem classe (`drivers/pci/setup-bus.c:184`). Isso foi reproduzido também com remove+rescan pelo sysfs. No LineageOS, quem faz isso é o driver do endpoint (`s51xx_pcie_probe()`):
    - grava `pci_db_addr` (`0x14D60000`) no BAR0 e relê, mascarado;
    - o offset do doorbell é `db_addr - BAR` (`0x60000` com o BAR0 de 1 MiB);
    - o doorbell fica no início da janela do root port (`bus->self->resource[8]`) mais o offset;
    - zera os BARs 1–5.

    O nosso driver do modem terá de fazer o mesmo, com o BAR0 dentro da janela atribuída à bridge.
  - O link negocia Gen4; o protótipo ficava em Gen1.
  - Falta MSI.
- Os scripts no aparelho ficam em `/usr/local/lib/r8s-modem/`, porque o `/tmp` é tmpfs.

## Memória compartilhada com o CP (levantamento, ainda não aplicado)

O LineageOS reserva (`exynos9830-rmem.dtsi`, compatível `exynos,modem_if`):

| Região | Endereço | Tamanho | `rmem_index` |
|---|---|---|---|
| `cp_rmem` (IPC) | `0xF0000000` | 8 MiB | 0 |
| `cp_msi_rmem` | `0xF6200000` | 4 KiB | 1 |
| `cp_rmem_2` (PKTPROC) | `0xD0000000` | 32 MiB no r8s (`exynos990-r8s_eur_open_05.dts`), 64 MiB na base | 2 |

**Conflito:** o port reserva `ramoops@f0000000` (4 MiB) no `exynos990-r8s.dts:172`, em cima do `cp_rmem`. Não se sabe se o firmware do CP espera esses endereços fixos. Decisão proposta: manter os endereços Samsung e mudar o `ramoops` de lugar antes de reservar as regiões do CP.

## Próximos marcos

4. **MAIN e NV pelo PCIe/shmem:** carregar o firmware principal e a calibração NV do EFS, depois o handshake SIPC5.
5. **Dados:** abrir o contexto PDP pelo protocolo IPC Samsung (FMT) e criar o `rmnet` sobre SBD/PKTPROC. É o trecho sem implementação aberta conhecida.
