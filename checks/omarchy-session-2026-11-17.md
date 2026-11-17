# Sessão Omarchy no aparelho — 17/11/2026

Continuação de `checks/arch-install-2026-11-17.md`. Telefone em Arch persistente.

## Rede e relógio

- Wi-Fi conectado (`wlp1s0`, 192.168.15.93) via NetworkManager; ping externo e DNS OK.
- Relógio estava ~30 dias atrasado (18/10), quebrando TLS; sincronizado manualmente e `timedatectl set-ntp true`. HTTPS para `pkgs.omarchy.org` respondeu 200.
- `pacman` 7.1 falhava com `Landlock is not supported by the kernel`: ativadas `DisableSandboxFilesystem` e `DisableSandboxSyscalls` em `/etc/pacman.conf` (kernel do port sem Landlock).

## Instalação

- Transferidos `packaging/omarchy/install-omarchy-r8s.sh`, `desktop-packages.txt` e `out/packages/mesa-g77-26.3.0_devel.7d6bb09d-2-aarch64.pkg.tar.xz` para `/tmp` do telefone.
- Instalador executado como root com `R8S_MESA_G77_PKG` apontando para o pacote: concluiu (`DONE`), log em `/tmp/omarchy-install.log` no telefone. Pacotes conferidos: `omarchy 4.5.0-3`, `hyprland 0.56.2-7`, `sddm 0.21.0-7`, `quickshell 0.3.2.r7…`, `uwsm 0.27.1-1`. Único erro: capabilities do `gst-ptp-helper` (irrelevante).

## Sessão gráfica (após reboot)

- `sddm.service` enabled/ativo com drop-in r8s; `default.target` = `graphical.target`; autologin `r8s` → `hyprland-uwsm.desktop`.
- `Hyprland` rodando; `quickshell -p /usr/share/omarchy/shell` rodando (shell real do Omarchy).
- `hyprctl monitors`: `DSI-1 1080x2400@60`, escala 2, focado, dpms on.
- Ambiente da sessão usa `/opt/mesa-g77` (`LD_LIBRARY_PATH`, EGL vendor, `PAN_MESA_DEBUG=noafbc`, ICD Panfrost) — renderer de hardware, não llvmpipe.

## Limites

Toque real, teclado virtual, brilho, áudio e estabilidade de longo prazo ainda não validados na sessão. Bluetooth segue com `-110` (patch `0106` não aplicado neste kernel). A tela física foi confirmada por processos/DRM via SSH; a conferência visual é do proprietário.
