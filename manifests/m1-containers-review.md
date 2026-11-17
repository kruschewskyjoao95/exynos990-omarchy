# Revisão offline: containers privilegiados, loop e caminhos fixos — 2026-11-17

Evidência do item M1 "Revisar uso de containers privilegiados, dispositivos loop, caminhos fixos, permissões e serviços de diagnóstico", lida por grep nas receitas em 17/11/2026. Nenhuma receita foi alterada aqui.

## Containers

- **Privilegiados**: `packaging/build-env/build-m1-rootfs.sh` (2×, slim Debian legado), `packaging/build-env/build-arch-rootfs.sh` (rootfs Arch + loop/pacman) e `packaging/mesa-g77/make-builder-image.sh` (builder Mesa). Sentido: montar loop/chroot dentro do container para montar imagem rootfs e instalar pacotes.
- **Sem `--privileged`**: `packaging/build-env/build-m1-kernel.sh`, `packaging/mesa-g77/build-mesa-g77.sh` (só `--platform`) e `checks/validate-arm64-userspace.sh` (montes somente leitura, sem dispositivos).
- `manifests/offline-validation.md` já registra: container ARM64 sem dispositivos ou modo privilegiado para a validação.

## Loop e mounts

- `build-arch-rootfs.sh` usa `losetup` e mounts `rbind`/`proc`/`sys` dentro do container para o chroot Arch; limpeza com `umount -R` (trava contra chroot montado, revisão `e86502e`).
- `make-builder-image.sh` faz `mount --rbind /dev` + `proc`/`sys` aninhados com `trap` de `umount EXIT`.
- `build-m1-rootfs.sh` (legado, rootfs Debian completo fora pela decisão de 17/11/2026) monta `proc/sys/dev` no slim.

## Caminhos fixos

- `/dev/sda32` em `build-arch-rootfs.sh` **não é arbitrário**: é o `userdata` verificado em `backups/partition-map.txt` (`boot` → `sda13`, `userdata` → `sda32`); o growroot usa `ConditionPathExists=/dev/sda32`.
- `/dev/cu.usbmodem*` em `sources/port/tools/r8s-serial.py` (upstream, não editar): WARN do preflight; no Linux usar `/dev/ttyACM*` (`manifests/m2-runbook.md`).

## Permissões e diagnóstico

- Receitas rodam como root dentro do container; no host, builds usam `docker run --rm` sem persistir container (o ARM64 opta por guardar o container parado em `validate` para inspeção). Ver `manifests/host-tools.md` para versões fixadas.
- O rootfs Arch rejeita `linux-*` genérico e o preflight `m2-preflight.sh` é somente leitura (nunca toca no telefone).
