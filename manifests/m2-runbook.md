# Runbook M2 sem aparelho — 2026-11-17

Pré-requisitos offline do M2 físico. Conjunto **baseline** (port + `0100`, `EXTRA_FIRMWARE=""`, sem `DEVFREQ_THERMAL`) — é o conjunto do 1º teste em RAM. Nada aqui grava o telefone; escrita só com ordem explícita do proprietário.

## Conjunto do 1º teste em RAM (hashes observados no computador)

- `out/boot/lk3rd-r8s.tar` `d999b844426f229742019b1cadf154ac95a90251a598dfa6708ee1ec1185c0e5` (560 KiB; `lk3rd-r8s.img` `48a15319a0ee3dcb65faaacaf51bd4bb897925c5efc03d19543eaa4afc4286ab`, 2 MiB)
- `Image` `cd727178582da65fe7ad99d083d2af838f2dd9fe274ce45a695fd6ada43be63d`; `r8s-ram.img` `fe07490f…` 63.150.080 B; `r8s-mini.img` `5b3545e6…` 24.672.256 B; rootfs `a2bcc167…` 734.003.200 B (detalhes em `manifests/m2-preflight-2026-11-17.md`)
- Guarda: `python3 checks/test-kernel-sets.py` falha se `out/boot/` deixar de ser baseline

## Antes de conectar o telefone (checklist do proprietário)

1. Cópia externa de `backups/` (fora do computador) e conferir na cópia com `(cd backups && sha256sum -c backup-manifest.sha256)` (10 OK). Nota: `backups/stock-backup-verify.txt` usa o formato `partição hash`, então `sha256sum -c` direto nele falha — quem confere esse arquivo é o `m2-preflight.sh --strict-backups`
2. Confirmação "sem dados pessoais a preservar" (M0) ou cópia dos dados
3. Ordem explícita do M2 (lk3rd + `fastboot boot` em RAM); gravar `lk3rd` já é alteração persistente

## Ao conectar (nessa ordem)

1. Recovery: `adb shell getprop ro.product.model` / `ro.product.device` — `packaging/host-tools/adb-common.sh` exige `SM-G780F`/`r8s` e recusa outros valores (falha segura). Sem `adb root` (`ro.debuggable=0`), a volta ao stock é pelo Download mode, não por `restore-stock.sh`
2. Download mode: `heimdall detect --verbose` deve responder. Antes de escrever, conferir no PIT do próprio aparelho o nome da partição BOOT, seu tamanho e a correspondência com `boot` → `sda13`. No Linux, o Heimdall recebe a imagem **crua** `out/boot/lk3rd-r8s.img` (2 MiB, SHA-256 `48a15319a0ee3dcb65faaacaf51bd4bb897925c5efc03d19543eaa4afc4286ab`). Somente após essa conferência, backups externos e ordem explícita do proprietário, o comando planejado é `heimdall flash --BOOT out/boot/lk3rd-r8s.img --no-reboot`. Não passar TAR ou LZ4 como conteúdo da partição. O arquivo `out/boot/lk3rd-r8s.tar`, contendo só `boot.img.lz4`, é o pacote para **Odin**, um procedimento separado. Depois da escrita, entrar no menu do lk3rd e conferir o fastboot antes do teste em RAM. Com `--no-reboot`, qualquer comando Heimdall posterior na mesma sessão precisa de `--resume`; não encadear uma nova escrita automaticamente.
3. RAM (nada gravado): `fastboot boot out/boot/r8s-mini.img` primeiro, depois `out/boot/r8s-ram.img`; recolher logs de boot e testar o console antes de qualquer gravação do rootfs
4. Mapa conferido no aparelho antes de gravar: `boot` → `sda13`, `userdata` → `sda32` (`backups/partition-map.txt`)

## Console USB no Linux

O preflight avisa que `sources/port/tools/r8s-serial.py` fixa `/dev/cu.usbmodem*` (macOS). No Linux usar `/dev/ttyACM*` com `minicom`/`picocom` (ou `screen`), sem editar o checkout do port. Nada foi testado no aparelho — queda de energia/bateria e cabos estão fora de escopo deste ensaio.

## Evidência offline do transporte

`python3 checks/test-m2-runbook.py` confere que o comando planejado usa a imagem crua, rejeita regressões para TAR/LZ4 e compara o conteúdo descomprimido de `boot.img.lz4` com `lk3rd-r8s.img`, byte a byte. Não executa Heimdall nem acessa USB. Isso não comprova aceitação pelo bootloader Samsung ou pelo Heimdall neste telefone.

Referência: [Heimdall — Flashing Firmware from Command Line](https://github.com/Benjamin-Dobell/Heimdall/blob/master/Linux/README#L164), que usa arquivos extraídos e nomes de partição obtidos do PIT. Ajuda local consultada: `heimdall help`, versão `v2.2.2`.
