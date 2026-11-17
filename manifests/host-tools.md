# Inventário do ambiente de build no computador (M1)

Verificado em: **2026-11-16**.

| Item | Observado no host | Observação para M1 |
| --- | --- | --- |
| Arquitetura / Kernel | `Linux 7.2.15-1-omarchy x86_64` | Host `x86_64`; execução ARM64 requer QEMU user-static / container `--platform linux/arm64` |
| Espaço livre em `/home` | `/dev/mapper/root  475G  244G  230G  52% /home` | Suficiente para checkouts, imagens e rootfs de staging |
| `binfmt_misc` (`qemu-aarch64`) | `presente` (`/usr/bin/qemu-aarch64-static`) | Execução de binários AArch64 em containers/chroots habilitada no kernel |
| Docker | `Docker version 29.9.3, build 5457199aa5` / daemon `29.9.2 overlayfs` | Pronto para containers `kbuild` (`amd64` + cross-compile) e `rootfsbuild` (`arm64` privilegiado isolado) |
| Git | `git version 2.56.1` | Disponível |
| Toolchain cross local | `aarch64-linux-gnu-gcc` ausente no host | Será provida dentro do container `kbuild` (ou pacote host separado) |
| Ferramentas Android/Samsung | `adb` (`Android Debug Bridge version 1.0.41 Version 37.0.0p1-android-tools`), `fastboot` (`fastboot version 37.0.0p1-android-tools`), `heimdall` (`v2.2.2`) | Prontas para M0/M2 quando o aparelho for conectado |
| `mkbootimg` | `/usr/bin/mkbootimg` | Conferir compatibilidade de argumentos com AOSP `mkbootimg.py --header_version 2` em `sources/port/tools/package-boot.sh` |
| `pacman` | `` | Disponível no host (`v7.1.0`) para inspeção isolada com `--root`/`--dbpath` |

## Referência Omarchy local (somente leitura)

- `/usr/share/omarchy/version`: `4.0.0.alpha`
- Confirmado em `/usr/bin/omarchy-hw-platform` e `/usr/bin/omarchy-lifecycle-dispatch`: plataformas registradas atualmente são `x86`, `aarch64`, `aarch64-apple`, `aarch64-qualcomm`, `aarch64-n1x`, `aarch64-gb10`; apenas `aarch64-apple` possui hooks ativos no dispatcher (`aarch64` genérico é no-op).
