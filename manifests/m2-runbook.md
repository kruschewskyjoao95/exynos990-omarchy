# Runbook M2 sem aparelho — 2026-11-17

Pré-requisitos offline do M2 físico. Conjunto **baseline** (port + `0100`, `EXTRA_FIRMWARE=""`, sem `DEVFREQ_THERMAL`) — é o conjunto do 1º teste em RAM. Nada aqui grava o telefone; escrita só com ordem explícita do proprietário.

## Conjunto do 1º teste em RAM (hashes observados no computador)

- `out/boot/lk3rd-r8s.tar` `d999b844426f229742019b1cadf154ac95a90251a598dfa6708ee1ec1185c0e5` (560 KiB; `lk3rd-r8s.img` `48a15319a0ee3dcb65faaacaf51bd4bb897925c5efc03d19543eaa4afc4286ab`, 2 MiB)
- `Image` `cd727178582da65fe7ad99d083d2af838f2dd9fe274ce45a695fd6ada43be63d`; `r8s-ram.img` `fe07490f…` 63.150.080 B; `r8s-mini.img` `5b3545e6…` 24.672.256 B; rootfs `a2bcc167…` 734.003.200 B (detalhes em `manifests/m2-preflight-2026-11-17.md`)
- Guarda: `python3 checks/test-kernel-sets.py` falha se `out/boot/` deixar de ser baseline

## Antes de conectar o telefone (checklist do proprietário)

1. Cópia externa de `backups/` (fora do computador) e conferir `sha256sum -c backups/stock-backup-verify.txt` — 8 entradas: `efs`, `sec_efs`, `cpefs`, `param`, `persistent`, `dtbo`, `boot`, `recovery`
2. Confirmação "sem dados pessoais a preservar" (M0) ou cópia dos dados
3. Ordem explícita do M2 (lk3rd + `fastboot boot` em RAM); gravar `lk3rd` já é alteração persistente

## Ao conectar (nessa ordem)

1. Recovery: `adb shell getprop ro.product.model` / `ro.product.device` — `packaging/host-tools/adb-common.sh` exige `SM-G780F`/`r8s` e recusa outros valores (falha segura). Sem `adb root` (`ro.debuggable=0`), a volta ao stock é pelo Download mode, não por `restore-stock.sh`
2. Download mode: `heimdall detect --verbose` deve responder; gravar `out/boot/lk3rd-r8s.tar` via heimdall (flags no `FLASHING.md` do port) e checar o menu/fastboot do lk3rd
3. RAM (nada gravado): `fastboot boot out/boot/r8s-mini.img` primeiro, depois `out/boot/r8s-ram.img`; recolher logs de boot e testar o console antes de qualquer gravação do rootfs
4. Mapa conferido no aparelho antes de gravar: `boot` → `sda13`, `userdata` → `sda32` (`backups/partition-map.txt`)

## Console USB no Linux

O preflight avisa que `sources/port/tools/r8s-serial.py` fixa `/dev/cu.usbmodem*` (macOS). No Linux usar `/dev/ttyACM*` com `minicom`/`picocom` (ou `screen`), sem editar o checkout do port. Nada был testado no aparelho — queda de energia/bateria e cabos estão fora de escopo deste ensaio.
