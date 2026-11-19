# Gravação do kernel de produção na partição `boot` (19/11/2026)

Ordem expressa do proprietário ("pode", depois de o plano e o backup serem descritos). Só a partição `boot` foi escrita; `lk3rd` (sda13) e o resto não foram tocados.

## O que foi gravado

- Imagem: `out/prod/boot/r8s-ufs.img`, 24.532.992 B, SHA-256 `7e65c291cb2ad373581b788411f8c6346e4c4c2deb0ded80070a04a79f2691dc`.
- Origem: `build-m1-kernel.sh all` com `R8S_KERNEL_PATCHSET=series` e `R8S_SKIP_PATCHES="0123 0124 0127 0128 0129 0131"` (os patches de câmera que não aplicam numa árvore nova). Série inclui `0100`-`0143`, `0145` (PHY SuperSpeed do USB 3, inerte sem o DT) e `0147` (opções de boot da GPU). `0146` (DT do USB 3) fica fora.
- Kernel `6.12.0-rc5-next-20241104-r8s` (sem `+`: casa com os módulos instalados), `bootargs` com `r8s_gpu_dvfs=1 panfrost.r8s_devfreq=1`.

## Antes e depois

- Backup: `backups/boot-sda33-20261119-before-prod.img`, 59.768.832 B (o tamanho exato da partição, `0x3900000`), SHA-256 `43265e2c60a3f36c3a25b58367c4cee7eb79c8dae3e3d523748bb401a02ae074`, igual no computador e no aparelho. Imagem de boot Android válida. Registrado em `backups/backup-manifest.sha256` (pasta ignorada pelo git).
- Gravação: `fastboot flash boot out/prod/boot/r8s-ufs.img` -> `OKAY` (0,9 s). Os primeiros 24.532.992 B da partição, relidos pelo aparelho, têm o mesmo SHA-256 da imagem.
- Teste em RAM antes de gravar (`fastboot boot`, mesma imagem): subiu inteira.

## Verificação no boot a frio (observado)

- Kernel `#1` com as opções da GPU na linha de comando; Wi-Fi `UP` em ~1 min (o `ath11k` espera ~60 s por `regulatory.db`, também no kernel anterior); `Hyprland`, `sddm`, `power-profiles-daemon`, `r8s-modem` ativos; nenhuma unidade falhou.
- `r8s-power-profile` iniciou sozinho (correção do ciclo de ordenação, `WantedBy=graphical.target`) e aplicou o perfil ativo, com a GPU em 156 MHz (devfreq).

## Restaurar o kernel anterior (#17)

Com o aparelho no fastboot (Power + Volume Baixo): `fastboot flash boot backups/boot-sda33-20261119-before-prod.img` e `fastboot reboot`.

## Fica de fora, por decisão

- Os 6 patches de câmera acima (a câmera está congelada), e o DT do USB 3 (`0146`, o link não treina).
