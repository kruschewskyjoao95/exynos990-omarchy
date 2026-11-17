# Coordenação entre agentes

Quadro compartilhado entre os agentes (Gemini/Antigravity, Claude Code) e o proprietário. Regras em [AGENTS.md](AGENTS.md#trabalho-com-mais-de-um-agente). Mantenha cada item em uma ou duas linhas; detalhes vão no commit ou no documento da etapa.

## Em andamento

<!-- - [agente] o que está fazendo. Arquivos: caminhos que vai alterar -->
- [claude] item 7b (pedido do proprietário: GPU é obrigatória): imagem Docker aarch64 de build + compilar `mesa-g77`. Arquivos: `packaging/mesa-g77/make-builder-image.sh` (novo), `out/build/`, `out/packages/`, `logs/mesa-g77-build.log`
- (gemini livre para análise não conflitante de firmwares Wi-Fi/BT em `blobs/r8s-device/vendor/` — aguardando autorização explícita do proprietário para iniciar M2 no aparelho)

## A fazer

Em ordem; pegar a primeira livre e mover para "Em andamento". Plano em [roadmap/00](roadmap/00-roadmap.md#ordem-de-execução-e-entregas).

7. [proprietário] Guardar cópia externa dos backups (`backups/`) e autorizar explicitamente o início de **M2** (`lk3rd` + `fastboot boot r8s-mini.img` / `r8s-ram.img` em RAM) após o ajuste de 6 GB.
7. [gemini] (após autorização de M2) Executar `packaging/host-tools/m2-preflight.sh`, gravar `lk3rd`, testar `r8s-mini.img` / `r8s-ram.img` em RAM e registrar logs/resultados (V2–V3).
7b. [gemini] Compilar o pacote `packaging/mesa-g77/` (nenhum `.pkg.tar.*` existe em 17/11/2026 06:20). Sem ele, `install-omarchy-r8s.sh` aborta ou roda sem GPU (`--allow-stock-mesa`). Pode ser feito no computador antes de M2; não precisa do aparelho.
9. [claude/gemini] (depois do teste em RAM do M2) DVFS da GPU: ACPM G3D = id 10 + tabela de 7 frequências, ver `roadmap/07` linha "Frequência variável da GPU". Primeiro só leitura de `get_rate(10)` no aparelho.
10. [gemini] Integrar `packaging/kernel-patches/series` em `build-m1-kernel.sh`: aplicar na ordem, depois dos 24 do port; `scripts/config -e DEVFREQ_THERMAL`. Manter um modo só com port+`0100` para o primeiro teste em RAM (ver `packaging/kernel-patches/README.md`).
11. [gemini] Rootfs Arch: instalar firmware Bluetooth `qca/htbtfw20.tlv` e `qca/htnv20.bin` (hoje não há nenhum `qca/`). Origem: `blobs/r8s-device/vendor/root/firmware/` ou linux-firmware; ver `research/wifi-bt-firmware.md`.
12. [claude] (no aparelho, depois do M2) testes por recurso, na ordem dos relatórios em `research/`: GPU DVFS só leitura, C2 na cpu7, timeouts I2C, BT com 115200/RTS, Wi-Fi com BDF próprio (exige `CONFIG_EXTRA_FIRMWARE` sem o `board-2.bin`), suspensão E1-E4, PWM antes do `0101`.
8. [claude] Revisar logs/artefatos gerados em M2–M4 no aparelho real antes de avançar para M5.

## Feito, aguardando revisão

<!-- - [agente] commit <sha>: resumo -->
- [gemini] commit `80667fc`: itens 1 e 2 concluídos — kernel `6.12.0-rc5-next-20241104-r8s` + `exynos990-r8s.dtb` + módulos, `initramfs-slim.cpio.gz` (Debian slim RAM-only, sem Debian completo), `r8s-ufs.img` (`27.785.216` B) e `r8s-ram.img` (`65.509.376` B ≤ `64 MiB`).
- [gemini] commit `5cfb7c3`: item 3 concluído — `packaging/build-env/build-arch-rootfs.sh` gera `out/rootfs/ufs-root.img` (`734.003.200` B / `700 MiB`, `610M` usados, `e2fsck -fn` ok), 160 pacotes `aarch64` sem `linux-*`, módulos + QCA6390 + `r8s-usb-gadget` (`10.42.0.2/24`) + `r8s-growroot` + `r8s-charge-limit` + `r8s-netwatch` + usuário `r8s` com SSH apenas por chave.
- [gemini] commit `7e9cb19`: item 4 concluído — `packaging/omarchy/install-omarchy-r8s.sh` configura `[omarchy]` stable antes de `[core]`/`[extra]`, valida `omarchy-keyring` por SHA-256 + PGP, bloqueia `linux-*`/`limine*`/`mkinitcpio*`, instala Omarchy + `foot`/`firefox`/`squeekboard` e adiciona glue `r8s` (`AQ_DRM_DEVICES`, `PAN_MESA_DEBUG=noafbc`, `r8s-unbind-fbcon`, `r8s-thermal-trip`, `r8s-recovery-vt`, overrides Lua em `~/.config/hypr/`).
- [gemini-swarm] commits `95b3ba1`, `c60351a`, `2360528`: item 5 revisado e corrigido no swarm — receita `packaging/mesa-g77/` (15 patches validados em `7d6bb09d`), correção dos módulos `0:0` + `r8s-mini.img` + `softdog`/watchdog/`pstore`/`r8s-heartbeat`/`r8s-safe-freq`/`sddm` DRM/PipeWire/toque, rebuild de `ufs-root.img` (`349c999e...`) e `r8s-mini.img` (`097cfbfa...`), `checks/verify-m1-m4-artifacts.sh` (**54/54 PASS**), `checks/test-flash-tools.sh` (**11/11 PASS**), `m2-preflight.sh` (**27 PASS / 2 WARN / 0 FAIL**) e `manifests/m1-artifacts.md`. *(Ainda sujeito à auditoria externa de `[claude]` quando disponível.)* Auditoria parcial do claude em 17/11/2026: 54/54 e 11/11 PASS reproduzidos; hashes de `r8s-ram`, `r8s-mini`, `lk3rd-r8s.tar` e `ufs-root.img` conferem; `root=/dev/sda32` do DTB bate com o rootfs; SSH por chave e login `r8s` com senha no `ttyGS0`. Não revisado linha a linha: `install-omarchy-r8s.sh`, `mesa-g77/PKGBUILD`, `rootfs-glue/*`.
- [gemini-swarm] coleta M0 somente leitura em Lineage Recovery (`uid=0`): dumps extras verificados em `backups/` (`up_param`, `vbmeta`, `r8s-ect.bin`, `partition-map.txt`, `lineage-*`, 10/10 `sha256sum -c` OK), `checks/m0-device-hardware.md` e `roadmap/03-primeira-sessao.md` atualizados sem PII. Descoberta crítica: `MemTotal: 5589576 kB` (`dram_info=01,07,00,6G`, **6 GB RAM** vs 8 GB no DTS do port), `sec_touchscreen` em `108d0000.hsi2c/i2c-5/5-0020`, `boot` (`sda13`) = `61.865.984` B (`59,0 MiB`).
- [gemini] commit `254670b`: item 6 concluído — `packaging/kernel-patches/0100-arm64-dts-exynos990-r8s-6gb-memory-map.patch` ajusta o banco alto de `memory@80000000` para `<0x8 0x80000000 0x0 0xfec00000>` (`0x9_7ec00000`, 20 MiB abaixo de `0x9_80000000`, deixando `el2_earlymem` `0x9_7ee00000..0x9_80000000` fora do mapa linear e mantendo a exclusão `s2mpu-table` em `0xc1b00000` de `0024`), `build-m1-kernel.sh` passa a aplicar `packaging/kernel-patches/*.patch` e ganha modo `dtbs`, e `exynos990-r8s.dtb` + `r8s-{ufs,ram,mini}.img` foram recompilados e verificados (`verify-m1-m4-artifacts.sh` **55/55 PASS**, `m2-preflight.sh --strict-backups` **32 PASS / 1 WARN / 0 FAIL**).

- [claude] commits `dfb0462`..`299b284`: patches extras `0101`-`0105` (subagentes, revisados pelo claude; `0102` corrigido para nunca deixar o Panfrost sem clock) e relatórios em `research/`. `series` = 0100, 0102-0105; aplicam em sequência sobre `r8s-port-base`. Kernel completo com a series: ver `logs/integ-kernel-build.log`.

## Revisão

<!-- - [revisor] <sha ou arquivo>: problema → ação esperada. Marque [x] quando o autor resolver. -->
- [x] [claude] `manifests/sources.md`: SHA do Omarchy `v4.5.0^{}` tem 39 caracteres (`…4a25f5e2…`). Correto, por `git ls-remote`: `ac2690cd7be4f47e4a255f5e2e78d904d436b068`. Corrigido pelo claude, commit "Corrige achados da revisão do baseline".
- [x] [claude] `sources/linux`: `.git` no commit certo (`75138397…`), mas a árvore de trabalho estava vazia (checkout incompleto em clone `blob:none`). Rodar `git -C sources/linux checkout -f HEAD` ou reclonar com `--depth 1`. Evitar `git diff`/`status` antes disso: dispara download de blobs. Observado às 00:27: árvore populada (corrigido pelo gemini).
- [x] [claude] `roadmap/00-roadmap.md`: ainda diz "Hoje só existem documentos" e M1 está todo desmarcado. Registrar o que já tem evidência (fontes fixadas, scripts adaptados + teste). Corrigido pelo claude, commit "Corrige achados da revisão do baseline"; status de `roadmap/05` também.
- [x] [claude] `logs/m1-build-lk3rd.log`: build do lk3rd falha em `lib/gpt/pit.c` com `bits/wordsize.h: No such file or directory` (headers x86 de `/usr/include` com compilador aarch64). Provável falta de `libc6-dev-arm64-cross` no `Dockerfile.kbuild`, ou usar o toolchain que `sources/lk3rd/scripts/` baixa. Hipótese, não testada. Resolvido pelo gemini: `out/boot/lk3rd-r8s.img` gerado às 00:26.
- [x] [claude] `checks/test-flash-tools.sh`: 11/11 PASS (testado no computador, `adb` simulado). Correção de `restore-stock.sh` (hash ausente era ignorado no original do port) observada no código.
- [x] [claude] `packaging/host-tools/*.sh`: exigem `adb root`, mas o aparelho conectado dá `id -u` = 2000 e `ro.debuggable=0` (lido em 17/11/2026, só leitura). Os scripts não servem no estado atual; documentar em `roadmap/05` qual caminho de gravação vale agora (Download/heimdall ou fastboot do lk3rd, conforme `sources/port/docs/FLASHING.md`). Falso alarme: o gemini gerou `lk3rd-r8s.tar` para Download mode, e `roadmap/05` (linhas 11 e 115) já registra a exigência de root. Sem `adb root`, a volta ao stock é pelo Download mode, não por `restore-stock.sh`.
- [x] [claude] `packaging/build-env/build-m1-kernel.sh` (`package_uniloader`): nada impede `r8s-ram.img` maior que 64 MiB. O lk3rd copia a imagem do `fastboot boot` para um buffer de 64 MiB sem checar o tamanho (`sources/lk3rd/app/exynos_boot/boot/mainline_boot.c:193-194`, observado no código). O port também não checa. Ação: abortar se `stat -c%s r8s-ram.img` > 67108864. Não editei: o script estava em execução. Resolvido em `80667fc` (trava > 67108864 + correção para não empacotar `ramdisk` duplicado no `mkbootimg`).
- [x] [claude] `packaging/build-env/build-m1-rootfs.sh`: senha root padrão `r8slab` + `PermitRootLogin yes` + `PasswordAuthentication yes`, com Wi-Fi via NetworkManager: SSH root com senha conhecida em qualquer rede em que o telefone entrar. Herdado do port; aceitável só em M2 em rede confiável. Ação: exigir `ROOTPW` sem valor padrão, ou SSH só por chave; já é requisito de M5 em `roadmap/00`. Resolvido em `80667fc` (`ROOTPW` obrigatório sem default; rootfs Debian completo removido).
- [x] [claude] `packaging/build-env/build-m1-rootfs.sh` (`build_slim`): remove módulos depois do `depmod`, então `modules.dep` lista arquivos apagados. Herdado do port (`sources/port/tools/build-slim-initramfs.sh:87-88`). Ação: rodar `depmod -b "$W" "$KVER"` de novo após os `rm`. Resolvido em `80667fc` (`depmod -b` após limpeza).
- [x] [claude] `packaging/build-env/build-m1-rootfs.sh` está fora do git e fora do quadro. Registrar em "Em andamento" e fazer commit ao concluir. Resolvido em `80667fc`.

## Decisões do proprietário

- [x] 17/11/2026: sem rootfs Debian completo. Teste em RAM com initramfs slim → Arch ARM mínimo gravado → Omarchy via `pacman`. Ver `roadmap/00`.
- [x] 17/11/2026: LineageOS 24.0 foi instalado pelo proprietário com ajuda do Gemini.

- [x] 17/11/2026: backup de `efs`, `sec_efs`, `cpefs`, `param`, `persistent`, `dtbo`, `boot` e `recovery` feito pelo claude via adb root do LineageOS Recovery, só leitura; hash e tamanho de cada imagem iguais ao aparelho. Em `backups/` (fora do git, somente leitura), hashes em `backups/stock-backup-verify.txt`. Falta o proprietário guardar uma cópia fora do computador.
- Escrita no telefone segue a regra 5 de [AGENTS.md](AGENTS.md#trabalho-com-mais-de-um-agente).
