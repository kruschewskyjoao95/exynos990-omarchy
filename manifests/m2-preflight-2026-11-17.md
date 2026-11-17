# Preflight offline M2 — 2026-11-17

Execução somente leitura de [`packaging/host-tools/m2-preflight.sh`](../packaging/host-tools/m2-preflight.sh) na branch `pr12-m2-preflight-offline` (baseada em `pr11-baseline-x-series`, conjunto **baseline** em `out/`).

- **Comando executado:** `./packaging/host-tools/m2-preflight.sh --probe-device --strict-backups`
- **Resumo:** **32 PASS / 1 WARN / 0 FAIL** (código de saída `0`).
- **Dispositivo USB anexado:** **nenhum** (`adb devices -l` vazio, `fastboot devices` vazio, `heimdall detect --verbose` retornou `ERROR: Failed to detect compatible download-mode device.`). Nenhuma escrita, flash, `lk3rd` ou `fastboot boot` foi executado.

## Resultados detalhados

### 1. Ferramentas do host (somente leitura)

| Verificação | Status | Detalhe observado |
|---|---|---|
| `tool-heimdall` | PASS | `/usr/bin/heimdall` (`v2.2.2`) |
| `tool-fastboot` | PASS | `/usr/bin/fastboot` (`fastboot version 37.0.0p1-android-tools`) |
| `tool-adb` | PASS | `/usr/bin/adb` (`Android Debug Bridge version 1.0.41`) |
| `tool-samloader` | PASS | `/home/joao/Downloads/s20fe-lineageos/samloader` (`samloader 2.2.0`) |
| `tool-r8s-serial` | **WARN** | `sources/port/tools/r8s-serial.py` sintaxe Python OK, mas fixa `/dev/cu.usbmodem*` (macOS; no Linux o console USB ACM aparece em `/dev/ttyACM*`) |

### 2. Artefatos em `out/`, limites de tamanho e blobs em `blobs/`

| Verificação | Status | Tamanho (bytes) | SHA-256 observado |
|---|---|---|---|
| `kernel-release` | PASS | — | `kernelrelease=6.12.0-rc5-next-20241104-r8s` |
| `out-lk3rd-img` | PASS | `2097152` | `48a15319a0ee3dcb65faaacaf51bd4bb897925c5efc03d19543eaa4afc4286ab` |
| `out-lk3rd-tar` | PASS | `573440` | `d999b844426f229742019b1cadf154ac95a90251a598dfa6708ee1ec1185c0e5` |
| `out-kernel-Image` | PASS | `23162888` | `cd727178582da65fe7ad99d083d2af838f2dd9fe274ce45a695fd6ada43be63d` |
| `out-kernel-dtb` | PASS | `83065` | `c406ea4e6c281c5e9ac89b3378779f02c04ce034a5c54e24dc43079f067a8c95` |
| `out-modules` | PASS | `8273653` | `4c7dc8e2581b7307b8ca8fdd456e1817a2838be6ca94960a8fd6d75ba0c4d13f` |
| `out-initramfs-slim` | PASS | `39494099` | `53a8ed4bee059b8c1a5d0c4d42c38d621cc9ac9d01c0058f041abade8e3ff659` |
| `out-initramfs-mini` | PASS | `1016955` | `7c3e26f1c985221bd1ae0bfdac9dffd93d2edeb3e2bd2ebad4733e6293beb649` |
| `out-r8s-ram` | PASS | `63150080` | `fe07490fc32195cb18037ac765c2087fa769dcbe1f908ba063a67aa87c415d61` |
| `out-r8s-mini` | PASS | `24672256` | `5b3545e61ca084b18e2e74eabf17e9defd3f91dc5544095b99db0321b2adf1c2` |
| `out-r8s-ufs` | PASS | `23656448` | `2cf80ae1d2434374ef3663a5dc59acecb214939ce77cbcc5d6696ed72915330d` |
| `out-ufs-root` | PASS | `734003200` | `a2bcc16796071e2f3eced7aa8a09a62599f01977a545bba128ba0ba2826461a0` |
| `budget-r8s-ram` | PASS | `63150080` | `<= 67108864` bytes (buffer de 64 MiB do `lk3rd`) |
| `budget-r8s-mini` | PASS | `24672256` | `<= 67108864` bytes (buffer de 64 MiB do `lk3rd`) |
| `budget-ufs-root` | PASS | `734003200` | `<= 734003200` bytes (700 MiB < buffer de 768 MiB do `lk3rd`) |
| `blob-slk-stock-dtb` | PASS | `340952` | `30c5769030bd4f801791c7888f8eb57ebc9e8fd944b88972800219d0355ab3f1` |
| `blob-qca-amss` | PASS | `3628672` | `8ab2a06422e3989012df423bb6a156fde2c3feb4cd5db4c5d3588f674dc872ff` |
| `blob-qca-m3` | PASS | `266684` | `1921d25edb52f90a7a0acc7275861e14399f904d579aae9f7ab1c4d28533fad6` |
| `blob-qca-board2` | PASS | `231980` | `4aa9f0fe15e9e2b6f9bb13b7187ed8ce035d9d46fb65fac5d5eba2c4e7edc091` |

### 3. Firmware stock e backups de partições (`--strict-backups`)

| Verificação | Status | Tamanho (bytes) | SHA-256 observado |
|---|---|---|---|
| `stock-boot.img` | PASS | `61865984` | `b33380a1aaf6be060bf2daad042b5c9c820105f3e3f03059c08d4551508a6487` |
| `stock-recovery.img` | PASS | `69009408` | `4dcf5c1ed3ed8663296af1b293b34dfbd3ebe2fdcf7042129ecc6d5bc27b8c58` |
| `stock-dtbo.img` | PASS | `8388608` | `dd34fe568804d726c454eeadaa378d80e91470abcfcda76abc0deae142084031` |
| `stock-boot-pin` | PASS | `61865984` | `b33380a1aaf6be060bf2daad042b5c9c820105f3e3f03059c08d4551508a6487` |
| `backup-boot` | PASS | `61865984` | `5a5bd79383d9c3836e5353da4546111a1c61e1e20d3cf3f9143d98160d4d0f7a` |
| `backup-recovery` | PASS | `69009408` | `7979e57224da6d4466b8ed3fd1e94051787daf87044979ea7866eecb953e14d4` |
| `backup-dtbo` | PASS | `8388608` | `82b59eba3f952bfbc73d9b866105e878783ef40ca5a89bd93b08bdea01c7bd0c` |
| `backup-efs` | PASS | — | Registrado em `backups/stock-backup-verify.txt` (`backups/stock-efs.img` presente) |
| `backup-sec_efs` | PASS | — | Registrado em `backups/stock-backup-verify.txt` (`backups/stock-sec_efs.img` presente) |

### 4. Sondagem de dispositivos (`--probe-device`) e bloqueios

- `adb devices -l`: `List of devices attached` (nenhum dispositivo).
- `fastboot devices`: vazio (nenhum dispositivo).
- `heimdall detect --verbose`: `ERROR: Failed to detect compatible download-mode device.`

**Bloqueios para iniciar M2 físico:**
1. **Dispositivo ausente:** nenhum SM-G780F/r8s anexado via USB hoje (`adb`/`fastboot`/`heimdall` sem alvo).
2. **Pré-requisitos pendentes em [`COORDENACAO.md`](../COORDENACAO.md):** cópia externa dos arquivos de `backups/` pelo proprietário e autorização explícita do proprietário para gravar `lk3rd` e iniciar os testes em RAM (`r8s-mini.img` / `r8s-ram.img`).
3. **Observação do WARN:** para console USB ACM no Linux durante M2, usar `/dev/ttyACM*` (ou `minicom`/`picocom`/`screen`) em vez do `/dev/cu.usbmodem*` fixado em `sources/port/tools/r8s-serial.py`.
