# Teclado virtual abrindo sozinho (19/11/2026)

Queixa: era preciso tocar no ícone do teclado (`r8s.osk`, que chama `~/.local/bin/r8s-osk-toggle`) para abrir e para fechar.

## Observado no aparelho (squeekboard 1.43.1, Hyprland 0.56.2)

- O squeekboard já abre e fecha pelo foco de campo de texto (D-Bus `sm.puri.OSK0` `Visible`):
  - `foot`: `Visible` vira `true` ao focar o terminal e volta a `false` ao fechar. Sem configuração extra.
  - `google-chrome` **sem flags**: não usa o protocolo; precisava do ícone.
  - `google-chrome` **com** `--enable-wayland-ime --wayland-text-input-version=3`: numa página `data:` com `<input autofocus>`, `Visible` = `true`.
- `QT_IM_MODULE=fcitx` vem de `/usr/share/omarchy/default/environment.d/10-omarchy-fcitx.conf` e `fcitx5` não roda: apps Qt não avisariam o squeekboard. Nenhum app Qt está instalado no aparelho; não alterado.
- Não testado: Firefox (GTK, deve usar text-input-v3 sem flags) e o fechamento do teclado ao tocar fora do campo dentro do Chrome.

## Mudança

`packaging/omarchy/r8s-chrome-ime-flags.sh` acrescenta as duas flags a `~/.config/chrome-flags.conf` e `chromium-flags.conf` (backups `*.bak-osk` no aparelho). Vale para janelas novas do Chrome. O ícone continua como alternativa manual.
