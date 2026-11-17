# Primeira sessão prática

Objetivo: fechar o inventário e preparar fontes reproduzíveis. O modelo **SM-G780F / Exynos 990** já foi confirmado pelo proprietário. Os campos abaixo permanecem pendentes; não inferir o estado atual a partir de conversas antigas.

## Inventário (atualizado em 17/11/2026)

| Informação | Registro |
| --- | --- |
| Modelo / placa confirmados | `SM-G780F` / `r8s` (`r8sxx`); DT `Samsung R8S EUR OPEN 05 based on EXYNOS990` (`androidboot.revision=5`, `dtbo_idx=2`, observado em Lineage Recovery) |
| Android/ROM e número da compilação | `LineageOS 24.0-20261116-NIGHTLY-r8s` (`userdebug`, `ro.build.version.release=17` no recovery; base `samsung/r8sxx/r8s:11/RP1A.200720.012/G780FXXSOFYJ1:user/release-keys`, CSC `ZTO`/`ZVV`) |
| Kernel e CPU em execução (recovery) | `4.19.325-cip126-st10-g97369af7bbd6` (`aarch64`); 4x Cortex-A55 (`0xd05`), 2x Cortex-A76 (`0xd0b`), 2x Samsung M5 (`0x004`) |
| Memória RAM real (observado em recovery) | **Variante 6 GB** (`MemTotal: 5589576 kB`, `androidboot.ddr_size=6`, `sec_debug.dram_info=01,07,00,6G`) — **atenção:** o DTS do port r8s declara 8 GB e precisa ser ajustado antes de M1/M2 |
| Versão e estado do bootloader | `G780FXXSOFYJ2`; bootloader desbloqueado (`ro.boot.warranty_bit=1`, `verifiedbootstate=orange`, `rp=24`) |
| Capacidade de armazenamento | UFS `13100000.ufs`: `sda` `127.934.660.608 B` (`119,15 GiB`); `userdata` (`sda32`) `116.253.523.968 B` (`108,27 GiB`) |
| Mapa de partições reais (`/dev/block/by-name/`) | Todas as 38 entradas mapeadas em Lineage Recovery ([m0-device-hardware.md](../checks/m0-device-hardware.md)): `boot` → `sda13` (`61.865.984 B` / `59,0 MiB`), `recovery` → `sda14` (`69.009.408 B` / `65,8 MiB`), `dtbo` → `sda11` (`8.388.608 B`), `efs` → `sda1` (`20.971.520 B`), `sec_efs` → `sda2` (`20.971.520 B`), `cpefs` → `sdd1` (`6.291.456 B`), `userdata` → `sda32` (`116.253.523.968 B`) |
| Tela e touch (observado em recovery) | Painel `SDC_800042` (`lcdtype=8388674`, `fb0` `19050000.decon_f`, `1080x2400` 32bpp, `stride=4320`, `backlight` `121/486`); touch `sec_touchscreen` em `108d0000.hsi2c/i2c-5/5-0020` (`0..1079` × `0..2399`, 10 contatos) |
| Recovery instalado e acesso a Download | `Lineage Recovery` (Volume - + Power até apagar → Volume +); Modo Download validado com `heimdall` / `odin` (`samloader v2.2.0` também disponível) |
| Root disponível e método | `ro.debuggable=0` no Android normal; `uid=0` (`u:r:su:s0`) confirmado via ADB em **Lineage Recovery** |
| Backup externo de dados pessoais | Sem dados pessoais a preservar; backups binários de partições críticas (`efs`, `sec_efs`, `cpefs`, `param`, `up_param`, `lineage-boot`, `lineage-recovery`, `lineage-dtbo`, `vbmeta`, `r8s-ect.bin`) extraídos e verificados por `sha256sum` em `backups/` (fora do Git) |
| Firmware stock correspondente e recuperação | Baixado e verificado via `samloader`: `G780FXXSOFYJ2/G780FOWOOFYJ2/G780FXXSOFYJ1/G780FXXSOFYJ2` (`SM-G780F`, `ZTO`) em `~/Downloads/s20fe-stock/`; extraídos `boot.img`, `recovery.img`, `dtbo.img` e `blobs/slk-stock.dtb` (`30c57690...`) |
| Bateria, cabo USB e estabilidade da conexão | ADB estável em Lineage Recovery; lido `capacity=100`, `voltage_now=4362000`, `charge_full=2927000`, `charge_full_design=4500000`, `batt_temp=334`. **Aviso:** leitura em lote com curinga em `/sys/class/power_supply/battery/*` causou reset USB/kernel após `charge_now`; evitar curingas nesse diretório |

Telemetria sanitizada completa e lista dos itens ainda pendentes (`memory*` DT para os 6 GB, `thermal_zone*`, `i2c`/`spi`, lista completa de `power_supply` e `dmesg`) estão registradas em [checks/m0-device-hardware.md](../checks/m0-device-hardware.md).

Se o Android estiver acessível e o computador já tiver ADB autorizado, estas leituras ajudam a preencher o inventário. Escolher explicitamente o aparelho se houver mais de um conectado; não publicar identificadores pessoais nos relatórios.

```sh
adb devices -l
adb shell getprop ro.product.model
adb shell getprop ro.product.device
adb shell getprop ro.build.fingerprint
adb shell getprop ro.bootloader
adb shell getprop ro.boot.flash.locked
adb shell id
```

Uma propriedade vazia ou um usuário não-root não determina sozinho todas as possibilidades. Se ADB não estiver autorizado ou o Android não iniciar, coletar pela tela e modos disponíveis; não desbloquear nem gravar partições para preencher o inventário.

## Preparação no computador

- [ ] Clonar fontes em diretórios separados, sem executar instaladores.
- [ ] Registrar SHA completo de cada checkout e ler as instruções aplicáveis.
- [ ] Revisar requisitos de build e scripts específicos de host em [01-base-s20fe.md](01-base-s20fe.md).
- [ ] Definir local externo para backups e espaço para imagens; guardar hashes e comprovar leitura das cópias.
- [ ] Produzir receita de build reproduzível antes de preparar qualquer escrita no telefone.

Não há comandos de flash neste documento: o procedimento concreto depende do inventário, do layout de armazenamento e das imagens verificadas. O próximo marco a concluir é **M0**, seguido pelo build **M1**; instalar o sistema é uma etapa posterior.
