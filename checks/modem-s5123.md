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

## Próximos marcos

3. **PCIe1** (`pcie@13D20000`, PERST, S2MPU): o endpoint Shannon enumera no `lspci`.
4. **MAIN e NV pelo PCIe/shmem:** carregar o firmware principal e a calibração NV do EFS, depois o handshake SIPC5.
5. **Dados:** abrir o contexto PDP pelo protocolo IPC Samsung (FMT) e criar o `rmnet` sobre SBD/PKTPROC. É o trecho sem implementação aberta conhecida.
