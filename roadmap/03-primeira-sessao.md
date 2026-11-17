# Primeira sessão prática

Objetivo: fechar o inventário e preparar fontes reproduzíveis. O modelo **SM-G780F / Exynos 990** já foi confirmado pelo proprietário. Os campos abaixo permanecem pendentes; não inferir o estado atual a partir de conversas antigas.

## Inventário (atualizado em 17/11/2026)

| Informação | Registro |
| --- | --- |
| Modelo / placa confirmados | `SM-G780F` / `r8s` (`r8sxx`) |
| Android/ROM e número da compilação | `LineageOS 24.0-20261116-NIGHTLY-r8s` (`userdebug`, base `samsung/r8sxx/r8s:11/RP1A.200720.012/G780FXXSOFYJ1:user/release-keys`, CSC `ZTO`) |
| Versão e estado do bootloader | `G780FXXSOFYJ2`; bootloader desbloqueado (`ro.boot.warranty_bit=1`) |
| Capacidade de armazenamento | `/data` (`userdata` → `/dev/block/sda32`): `108G` totais (`105G` livres) |
| Mapa de partições reais (`/dev/block/by-name/`) | `boot` → `/dev/block/sda13`, `recovery` → `/dev/block/sda14`, `dtbo` → `/dev/block/sda11`, `userdata` → `/dev/block/sda32` |
| Recovery instalado e acesso a Download | `Lineage Recovery` (Volume - + Power até apagar → Volume +); Modo Download validado com `heimdall` / `odin` (`samloader v2.2.0` também disponível) |
| Root disponível e método | `ro.debuggable=0` no Android atual (`adb root` desabilitado nas configurações); gravação/recuperação inicial via Modo Download + Lineage Recovery (`~/Downloads/s20fe-lineageos`) |
| Backup externo de dados pessoais | Sem dados pessoais a preservar (aparelho recém-instalado com LineageOS) |
| Firmware stock correspondente e recuperação | Baixado e verificado via `samloader`: `G780FXXSOFYJ2/G780FOWOOFYJ2/G780FXXSOFYJ1/G780FXXSOFYJ2` (`SM-G780F`, `ZTO`) em `~/Downloads/s20fe-stock/`; extraídos `boot.img`, `recovery.img`, `dtbo.img` e `blobs/slk-stock.dtb` (`30c57690...`) |
| Bateria, cabo USB e estabilidade da conexão | Cabo USB e ADB estáveis na porta USB do host; leitura de bateria via sysfs bloqueada para usuário `shell` sem root |

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
