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

## Toque e atalho do menu

- Captura de eventos (`/dev/input/event0`): coordenadas na tela inteira (x 57–1016, y 38–2350) — sensor e mapeamento corretos. O que não respondia era o botão do menu no shell.
- Causa parcial: faltava `socat` no telefone; sem ele, `omarchy-shell` (IPC do shell) falha antes do fallback `qs ipc`. Instalado via pacman; `omarchy-shell shell ping` responde `ok`.
- Atalho criado em `~/.local/share/applications/omarchy-menu.desktop` ("Omarchy Menu", ícone `omarchy`): executa `omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'`, o mesmo comando do botão. Aparece na grade de apps junto de Firefox/Foot. Teste de toggle via SSH: rc=0.
- Correção pós-teste: `toggle` no atalho falhava na segunda abertura (ficava só no OSD "Launching"); trocado para `summon` (sempre abre) + `StartupNotify=false`. Summon duplo via SSH: rc=0 e layer `omarchy-menu` presente.
- Item "About" do menu morria na hora: faltava o pacote `fastfetch` (`fastfetch: command not found` no terminal). Instalado via pacman; render do About conferido em pty (tela de Hardware/logo sai normalmente).
- Erro "input methods could not be updated [errno 2] 'fcitx5-remote'": faltava o `fcitx5` (o `omarchy-fcitx5.service` já estava enabled, mas inativo). Instalados `fcitx5`, `fcitx5-gtk`, `fcitx5-qt` (motores CJK do base upstream ficaram fora); serviço ativo, `omarchy input-method status` responde `{"installed_method": "none", "layout": "us"}`. Correção durável: os três pacotes entraram em `packaging/omarchy/desktop-packages.txt`.

## Limites

Teclado virtual, brilho, áudio e estabilidade de longo prazo ainda não validados na sessão. Bluetooth segue com `-110` (patch `0106` não aplicado neste kernel). A tela física foi confirmada por processos/DRM via SSH; a conferência visual é do proprietário.
