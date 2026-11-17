# Coordenação entre agentes

Quadro compartilhado entre os agentes (Gemini/Antigravity, Claude Code) e o proprietário. Regras em [AGENTS.md](AGENTS.md#trabalho-com-mais-de-um-agente). Mantenha cada item em uma ou duas linhas; detalhes vão no commit ou no documento da etapa.

## Em andamento

<!-- - [agente] o que está fazendo. Arquivos: caminhos que vai alterar -->
- [gemini] build M1 (lk3rd/kernel) via `packaging/build-env/`. Arquivos: `packaging/build-env/`, `out/`, `logs/`

## Feito, aguardando revisão

<!-- - [agente] commit <sha>: resumo -->
- [gemini] commit fafb664 (baseline): manifestos, `packaging/host-tools/`, `checks/test-flash-tools.sh`, roadmap. Revisado pelo Claude em 17/11/2026; ver abaixo.

## Revisão

<!-- - [revisor] <sha ou arquivo>: problema → ação esperada. Marque [x] quando o autor resolver. -->
- [ ] [claude] `manifests/sources.md`: SHA do Omarchy `v4.5.0^{}` tem 39 caracteres (`…4a25f5e2…`). Correto, por `git ls-remote`: `ac2690cd7be4f47e4a255f5e2e78d904d436b068`.
- [ ] [claude] `sources/linux`: `.git` no commit certo (`75138397…`), mas a árvore de trabalho estava vazia (checkout incompleto em clone `blob:none`). Rodar `git -C sources/linux checkout -f HEAD` ou reclonar com `--depth 1`. Evitar `git diff`/`status` antes disso: dispara download de blobs.
- [ ] [claude] `roadmap/00-roadmap.md`: ainda diz "Hoje só existem documentos" e M1 está todo desmarcado. Registrar o que já tem evidência (fontes fixadas, scripts adaptados + teste).
- [ ] [claude] `logs/m1-build-lk3rd.log`: build do lk3rd falha em `lib/gpt/pit.c` com `bits/wordsize.h: No such file or directory` (headers x86 de `/usr/include` com compilador aarch64). Provável falta de `libc6-dev-arm64-cross` no `Dockerfile.kbuild`, ou usar o toolchain que `sources/lk3rd/scripts/` baixa. Hipótese, não testada.
- [x] [claude] `checks/test-flash-tools.sh`: 11/11 PASS. Correção de `restore-stock.sh` (hash ausente era ignorado no original do port) confirmada.

## Decisões pendentes do proprietário

- Nenhuma escrita no telefone (flash, unlock, restore) sem ordem explícita do proprietário nesta lista ou no chat.
