# Coordenação entre agentes

Quadro compartilhado entre os agentes (Gemini/Antigravity, Claude Code) e o proprietário. Regras em [AGENTS.md](AGENTS.md#trabalho-com-mais-de-um-agente). Mantenha cada item em uma ou duas linhas; detalhes vão no commit ou no documento da etapa.

## Em andamento

<!-- - [agente] o que está fazendo. Arquivos: caminhos que vai alterar -->
- [gemini] build M1 (lk3rd/kernel) via `packaging/build-env/`. Arquivos: `packaging/build-env/`, `out/`, `logs/`

## A fazer

Em ordem; pegar a primeira livre e mover para "Em andamento". Plano em [roadmap/00](roadmap/00-roadmap.md#ordem-de-execução-e-entregas).

1. [gemini] Terminar kernel + initramfs slim + `r8s-ram.img` (teste em RAM), com o limite de 64 MiB da seção Revisão.
2. [gemini] **Não** rodar `build-m1-rootfs.sh rootfs` (Debian completo): fora do plano desde 17/11/2026. Manter só `build_slim`.
3. [gemini] Novo builder do rootfs Arch ARM mínimo (`ufs-root.img` ≤ 700 MiB): `base`, `archlinuxarm-keyring`, systemd, `networkmanager`, `openssh`, `sudo`, `e2fsprogs`; módulos do kernel M1; firmware QCA6390; `r8s-usb-gadget` + IP fixo `10.42.0.2`; `r8s-growroot`; usuário comum com SSH por chave. Pacotes e versões de `manifests/packages-aarch64-stable.tsv`, sem kernel genérico `linux-*`.
4. [gemini] Receita de instalação do Omarchy pós-boot (`[omarchy]` stable + `omarchy-keyring`, conforme `manifests/packages-aarch64.md`), sem rodar o instalador de PC (disco/ISO/bootloader).
5. [claude] Revisar 3 e 4 contra `sources/port/tools/build-rootfs.sh` e `build-ufs-image.sh` (serviços r8s que precisam existir no Arch).

## Feito, aguardando revisão

<!-- - [agente] commit <sha>: resumo -->
- (vazio; o baseline `fafb664` já foi revisado, achados abaixo)

## Revisão

<!-- - [revisor] <sha ou arquivo>: problema → ação esperada. Marque [x] quando o autor resolver. -->
- [x] [claude] `manifests/sources.md`: SHA do Omarchy `v4.5.0^{}` tem 39 caracteres (`…4a25f5e2…`). Correto, por `git ls-remote`: `ac2690cd7be4f47e4a255f5e2e78d904d436b068`. Corrigido pelo claude, commit "Corrige achados da revisão do baseline".
- [x] [claude] `sources/linux`: `.git` no commit certo (`75138397…`), mas a árvore de trabalho estava vazia (checkout incompleto em clone `blob:none`). Rodar `git -C sources/linux checkout -f HEAD` ou reclonar com `--depth 1`. Evitar `git diff`/`status` antes disso: dispara download de blobs. Observado às 00:27: árvore populada (corrigido pelo gemini).
- [x] [claude] `roadmap/00-roadmap.md`: ainda diz "Hoje só existem documentos" e M1 está todo desmarcado. Registrar o que já tem evidência (fontes fixadas, scripts adaptados + teste). Corrigido pelo claude, commit "Corrige achados da revisão do baseline"; status de `roadmap/05` também.
- [x] [claude] `logs/m1-build-lk3rd.log`: build do lk3rd falha em `lib/gpt/pit.c` com `bits/wordsize.h: No such file or directory` (headers x86 de `/usr/include` com compilador aarch64). Provável falta de `libc6-dev-arm64-cross` no `Dockerfile.kbuild`, ou usar o toolchain que `sources/lk3rd/scripts/` baixa. Hipótese, não testada. Resolvido pelo gemini: `out/boot/lk3rd-r8s.img` gerado às 00:26.
- [x] [claude] `checks/test-flash-tools.sh`: 11/11 PASS (testado no computador, `adb` simulado). Correção de `restore-stock.sh` (hash ausente era ignorado no original do port) observada no código.
- [x] [claude] `packaging/host-tools/*.sh`: exigem `adb root`, mas o aparelho conectado dá `id -u` = 2000 e `ro.debuggable=0` (lido em 17/11/2026, só leitura). Os scripts não servem no estado atual; documentar em `roadmap/05` qual caminho de gravação vale agora (Download/heimdall ou fastboot do lk3rd, conforme `sources/port/docs/FLASHING.md`). Falso alarme: o gemini gerou `lk3rd-r8s.tar` para Download mode, e `roadmap/05` (linhas 11 e 115) já registra a exigência de root. Sem `adb root`, a volta ao stock é pelo Download mode, não por `restore-stock.sh`.
- [ ] [claude] `packaging/build-env/build-m1-kernel.sh` (`package_uniloader`): nada impede `r8s-ram.img` maior que 64 MiB. O lk3rd copia a imagem do `fastboot boot` para um buffer de 64 MiB sem checar o tamanho (`sources/lk3rd/app/exynos_boot/boot/mainline_boot.c:193-194`, observado no código). O port também não checa. Ação: abortar se `stat -c%s r8s-ram.img` > 67108864. Não editei: o script estava em execução.
- [ ] [claude] `packaging/build-env/build-m1-rootfs.sh`: senha root padrão `r8slab` + `PermitRootLogin yes` + `PasswordAuthentication yes`, com Wi-Fi via NetworkManager: SSH root com senha conhecida em qualquer rede em que o telefone entrar. Herdado do port; aceitável só em M2 em rede confiável. Ação: exigir `ROOTPW` sem valor padrão, ou SSH só por chave; já é requisito de M5 em `roadmap/00`.
- [ ] [claude] `packaging/build-env/build-m1-rootfs.sh` (`build_slim`): remove módulos depois do `depmod`, então `modules.dep` lista arquivos apagados. Herdado do port (`sources/port/tools/build-slim-initramfs.sh:87-88`). Ação: rodar `depmod -b "$W" "$KVER"` de novo após os `rm`.
- [ ] [claude] `packaging/build-env/build-m1-rootfs.sh` está fora do git e fora do quadro. Registrar em "Em andamento" e fazer commit ao concluir.

## Decisões do proprietário

- [x] 17/11/2026: sem rootfs Debian completo. Teste em RAM com initramfs slim → Arch ARM mínimo gravado → Omarchy via `pacman`. Ver `roadmap/00`.
- [x] 17/11/2026: LineageOS 24.0 foi instalado pelo proprietário com ajuda do Gemini.

- [ ] Backup de `efs`/`sec_efs` (IMEI): sem `adb root` não há cópia, e o firmware stock não restaura essas partições. Opções: obter root para copiar antes do primeiro flash, ou aceitar o risco por escrito. O port não grava essas partições (`sources/port/tools/restore-stock.sh`, lista de nunca gravar).
- Escrita no telefone segue a regra 5 de [AGENTS.md](AGENTS.md#trabalho-com-mais-de-um-agente).
