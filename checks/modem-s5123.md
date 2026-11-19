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

## Marco 3: PCIe canal 1 (bloqueado)

O controlador do modem é o **GEN4_1 do HSI2** (`pcie@13D20000`), um IP diferente do GEN2/HSI1 do Wi-Fi, que é o que o `pci-exynos.c` do port suporta. O protótipo `packaging/modem/cp-pcie-link.py` reproduz pelo `/dev/mem` a sequência `exynos_pcie_rc_poweron()`/`establish_link()` e a calibração `chip_ver=1` de `pcie-exynos9830-rc-cal.c` (cerca de 140 escritas literais).

**Resultado: o primeiro acesso ao ELBI (`0x13D202C8`) trava o SoC.** É um travamento seco, sem panic e sem pstore, e o watchdog reinicia o aparelho. Isso foi reproduzido numa sondagem só de leitura com o CP desligado. PMU `0x720` (=0) e SYSREG_HSI2 `+0x0`/`+0x800` (=0/`0x81084`) leem normalmente.

Verificado ativo, ou seja, não é clock:

| Bloco | Estado |
|---|---|
| CMU_TOP | `hsi2_bus` 200 MHz e `hsi2_pcie` 800 MHz, hw enable `Y` |
| CMU_HSI2, `MUX_USER` | `BUS_USER`/`PCIE_USER` = `0x10` (CMU selecionado) |
| CMU_HSI2, gates do GEN4_1 | `0x2018`–`0x2030` e `0x204c` = `0x200000` |
| CMU_HSI2, QCH | `0x3028`–`0x3038` = `0x3f0002` |
| Barramento e reset-sync | LHM/LHS/XIU/RSTNSYNC/SYSREG/D_TZPC = `0x200000` |

No LineageOS o probe do `exynos-pcie-rc` acessa o ELBI (`enable_interrupts(pp, 0)`) antes de qualquer ajuste de PMU e sem clocks próprios (`pcie-clk-num = <0>`). Então lá o bloco já está acessível. Hipóteses abertas, não testadas:
- reset ou isolamento de energia do sub-bloco PCIe do HSI2 deixado pelo caminho de boot (S-Boot → lk3rd → uniLoader);
- proteção TrustZone (`D_TZPC_HSI2`) marcando o GEN4_1 como seguro.

Para o marco 4, há chamadas SMC de verificação de boot do CP em `cpif/link_device.c:2280-2293` (`exynos_smc(SMC_ID, msr.mode…)`, `MODE_CP_CHECK_CONTINUE`). A EL3 provavelmente valida o firmware MAIN antes de liberar o CP.

## Próximos marcos

3. **PCIe1** (`pcie@13D20000`, PERST, S2MPU): o endpoint Shannon enumera no `lspci`.
4. **MAIN e NV pelo PCIe/shmem:** carregar o firmware principal e a calibração NV do EFS, depois o handshake SIPC5.
5. **Dados:** abrir o contexto PDP pelo protocolo IPC Samsung (FMT) e criar o `rmnet` sobre SBD/PKTPROC. É o trecho sem implementação aberta conhecida.
