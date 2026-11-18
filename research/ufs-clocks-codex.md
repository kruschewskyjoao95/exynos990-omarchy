# UFS e clocks — diagnóstico do baseline no SM-G780F

Coleta do codex em 17/11/2026. **[código]** = fonte fixada ou DTB inspecionado; **[aparelho]** = observado neste r8s; **[hipótese]** e **[proposta]** não são correções validadas. Relatório separado porque o Claude assumiu `research/ufs-clocks.md` durante a coleta. Nenhum patch aplicado nesta investigação.

## Resultado

**[aparelho]** UFS negociou `FAST_MODE / HS_RATE_B / HS_GEAR3`, duas lanes, dispositivo e link `ACTIVE`. Três leituras diretas completas de recovery e DTBO produziram os hashes conhecidos dos backups, sem novos registros no dmesg nem aumento nos contadores de erro UFS. Isso demonstra leitura dessas regiões neste boot; não aprova escrita, carga prolongada ou suspensão.

**[código + aparelho]** Os erros `exynos-clkout -22` e `18c00000.clock-controller -110` têm causas distintas do caminho de clocks do UFS. O primeiro é uma tabela de compatibilidade incompleta para a PMU declarada no DT. O segundo é dependência do domínio **AUD desabilitado**, não uma medição de falha do clock UFS e nem evidência de timeout ao energizar AUD.

## Baseline e reprodução

- Kernel base: `75138397b8f856193bf344a21a1e1e98179f0901`, port `e21bfa3f0fd2f15e9e5b0919df44b61d6faba217`, patches do port + ajuste local 0100 de RAM de 6 GB. Sem a série experimental 0102–0105.
- Kernel executado: `6.12.0-rc5-next-20241104-r8s`.
- `out/boot/r8s-ram.img`: SHA-256 `fe07490fc32195cb18037ac765c2087fa769dcbe1f908ba063a67aa87c415d61`, conferido antes de `fastboot boot`.
- `out/boot/exynos990-r8s.dtb`: SHA-256 `c406ea4e6c281c5e9ac89b3378779f02c04ce034a5c54e24dc43079f067a8c95`. DTB decompilado com o `scripts/dtc/dtc` do build; propriedades relevantes também conferidas no DT vivo.
- Slim Debian somente em RAM, rootfs e pseudo-filesystems; nenhuma partição UFS montada. Modelo previamente confirmado SM-G780F/r8s; `fastboot getvar product` confirmou `r8s - lk3rd` antes do ensaio.
- Critério da reprodução: reaparecerem os quatro avisos DME; critério do ensaio de leitura: comandos concluírem, seis hashes coincidirem com os backups, dmesg permanecer igual entre leituras e contadores UFS permanecerem zerados.

## 1. Os quatro avisos UFS

**[aparelho]** Neste boot, entre 0,410 e 0,411 s:

```text
dme-set: attr-id 0x9540 val 0x1 failed 0 retries
dme-set: attr-id 0x321 val 0xd failed 0 retries
dme-set: attr-id 0x321 val 0xd failed 0 retries
dme-set: attr-id 0x9540 val 0x0 failed 0 retries
Power mode changed to : FAST series_B G_3 L_2
```

**[código]** Correspondência exata na árvore aplicada `out/work/linux`:

| Origem | O que faz |
| --- | --- |
| `drivers/ufs/host/ufs-exynos.c`, `exynos_ufs_pre_pwr_mode()` | Chama `exynos_ufs_config_sync_pattern_mask()` ao negociar modo HS. |
| Mesma unidade, `exynos_ufs_config_sync_pattern_mask()` | Habilita override de temporização, escreve a máscara em cada lane RX e desabilita override. |
| `drivers/ufs/host/ufs-exynos.h` | Define `PA_DBG_OV_TM = 0x9540` e `RX_SYNC_MASK_LENGTH = 0x0321`; helpers escrevem 1 e 0 em `PA_DBG_OV_TM`. |
| `drivers/ufs/core/ufshcd.c`, `ufshcd_dme_set_attr()` | Emite o aviso quando o retorno do comando UIC é diferente de zero. Repete automaticamente somente comandos *peer*. |

**`failed 0 retries` não significa retorno zero.** Significa que o comando local falhou sem tentativas adicionais. O código numérico fica no `dev_dbg`; não apareceu no log coletado e `CONFIG_DYNAMIC_DEBUG` está desabilitado no baseline. Portanto, a razão UIC exata da rejeição ainda não foi comprovada.

**[código]** A função de máscara é `void`, ignora os retornos e o caminho de negociação continua. A opção `EXYNOS_UFS_OPT_SKIP_CONFIG_PHY_ATTR` do Exynos 990 evita outras configurações genéricas da PHY, mas não evita esta função. A ordem dos quatro avisos coincide com override → lane 0 → lane 1 → override.

**[hipótese]** Essa sequência genérica de atributos não é adequada ao caminho embedded do Exynos 990. A calibração embedded em `sources/lk3rd/platform/exynos9830/ufs-cal-9830.c` usa programação própria de PHY/UniPro e não contém os atributos 0x9540/0x321. Isso orienta a investigação, mas não prova que remover a sequência seja suficiente ou correto no Linux.

**[proposta]** Antes de corrigir, expor o retorno UIC em um build de diagnóstico isolado e comparar a sequência com a calibração Samsung/embedded. Se a incompatibilidade for confirmada, restringir a mudança ao Exynos 990 e repetir leitura, negociação e retorno ao loader. Não transformar essas chamadas em falha fatal global, não alterar todos os Exynos e não apenas ocultar o log.

Fonte primária fixada: [driver UFS da base selecionada](https://raw.githubusercontent.com/exynos990-mainline/linux/75138397b8f856193bf344a21a1e1e98179f0901/drivers/ufs/host/ufs-exynos.c), conferido contra a árvore com os patches locais aplicados.

## 2. Leituras e contadores

**[aparelho]** Conferidos os labels `sda14=recovery` e `sda11=dtbo`, com aborto se houvesse `/dev/sd*` montado. Executado em subshell Bash com `set -euo pipefail`, três vezes:

```sh
dd if=/dev/sda14 bs=1M iflag=direct status=none | sha256sum
dd if=/dev/sda11 bs=1M iflag=direct status=none | sha256sum
```

| Região | SHA-256 em cada uma das três leituras |
| --- | --- |
| Recovery | `7979e57224da6d4466b8ed3fd1e94051787daf87044979ea7866eecb953e14d4` |
| DTBO | `82b59eba3f952bfbc73d9b866105e878783ef40ca5a89bd93b08bdea01c7bd0c` |

Os seis resultados coincidem com os backups anteriores à instalação de lk3rd. `iflag=direct` evita que o conteúdo seja atendido pelo cache de páginas do Linux; não é uma medição de desempenho nem um teste de toda a unidade.

Antes e depois, `/sys/kernel/debug/ufshcd/13100000.ufs/stats` apresentou zero em todos os 13 contadores: camadas PHY/link/rede/transporte/DME, auto-hibernate, fatal, link startup, PM resume/suspend, resets de unidade/host e abortos SCSI. `saved_err` e `saved_uic_err` também foram zero. `diff` dos snapshots de dmesg antes/depois não produziu linhas.

Esses contadores não registram necessariamente toda rejeição de comando de configuração: os quatro avisos iniciais coexistem com estatísticas zeradas. Não usar os zeros para declarar os avisos corrigidos. O relógio do telefone ainda mostrou abril/2026; a data desta coleta vem da sessão do host, não do RTC do aparelho.

## 3. Timeout do controlador de áudio

**[código + aparelho]** `clock-controller@18c00000` é `samsung,exynos990-cmu-aud`. Seu `power-domains` aponta para `pd_aud`, cujo `status` vivo é `disabled`.

O patch 0005 do port desabilita deliberadamente `pd_aud`: seu comentário registra SError na sequência TZPC de suspensão e orienta reativá-lo junto do trabalho de áudio. Entretanto, o consumidor `cmu_aud` permanece habilitado.

Em `drivers/pmdomain/core.c`, `__genpd_dev_pm_attach()` não encontra o provider desabilitado e retorna `driver_deferred_probe_check_state()`. Em `drivers/base/dd.c`, essa rotina retorna `-ETIMEDOUT` (-110) depois do prazo de deferred probe. Isso explica o log em 13,288 s sem pressupor falha física de energização. O resumo genpd do aparelho listou apenas G3D, sem AUD.

**[proposta]** Para o perfil atual sem áudio interno, desabilitar também `cmu_aud` no DTS r8s, após revisar seus consumidores. Manter `pd_aud` desabilitado. Reabilitar o domínio para eliminar o aviso reintroduziria a sequência que o port evita. Correção ainda não aplicada nem testada nesta coleta.

## 4. CLKOUT e os clocks usados pelo UFS

**[código + aparelho]** O pai de `exynos-clkout` é o nó `system-controller@11860000`, cujo `compatible` vivo é `samsung,exynos850-pmu`, `syscon`; seu `reg` aponta para 0x15860000. O nome/endereço unitário do nó não deve ser confundido com a base MMIO.

`drivers/soc/samsung/exynos-pmu.c` aceita esse compatible e instancia o filho `exynos-clkout`. Já `drivers/clk/samsung/clk-exynos-clkout.c`, em `exynos_clkout_match_parent_dev()`, não contém Exynos 850/990 na tabela de pais: emite `cannot match parent device` e retorna `-EINVAL` (-22) antes de registrar o clock de saída.

O DT do UFS usa outro provider: `ufs-core-clock`, fixed-clock de **166.562.500 Hz**, tanto em `core_clk` quanto em `sclk_unipro_main`. A PHY usa `oscclk` como `ref_clk`, independente de CLKOUT/AUD; o fixed-clock chamado `ufs-unipro` não é o provider dessas duas entradas do host. No aparelho, o debugfs do provider fixo reportou taxa 166562500, enable count 2 e prepare count 2; `DBG pre_link mclk=166562500` concordou. Isso confirma a configuração vista pelo Linux, **não mede a frequência física** nem comprova correção da gestão de energia.

`clk: Not disabling unused clocks` corresponde a `clk_ignore_unused` na cmdline. É uma escolha explícita do baseline; remover esse parâmetro para limpar o log seria um teste diferente, com risco de desligar clocks herdados do bootloader.

**[proposta]** Tratar CLKOUT separadamente, sem inventar compatible de outra PMU ou mudar clocks UFS. Implementar suporte correto ou limitar a criação do filho às variantes suportadas, se necessário. Não há evidência de dependência do UFS desse CLKOUT na configuração testada.

## Evidências locais e estado final

Snapshots fora do Git, preservados com prefixo próprio para evitar sobreposição com a sessão do Claude:

| Arquivo em `logs/` | SHA-256 |
| --- | --- |
| `m2-codex-ufs-boot.log` | `325ec54d16ccb13c62f54814cd783fd6d08e77b353e586c605e61aed8cc1ad34` |
| `m2-codex-ufs-before.log` | `df7ef338571a2872f6d124280bd725986c811e57e1b0fdd0bf7f886b9fb91cdb` |
| `m2-codex-ufs-direct-reads.log` | `3b8152fe3626924e53c84b46e04dec0cf93e232fb527349ad378ceeee2dc7e4e` |
| `m2-codex-clocks-native.log` | `e6944f84a42f246ae6bc6cd76bacd99bfa515a2e5bc5193062d2639f449b15a3` |

O último log contém fragmentos antigos depois do marcador `CLOCKS_DONE`; a análise usa a resposta anterior a esse marcador. Ao identificar no quadro a tomada da tarefa pelo Claude, interrompi os comandos USB. Nenhum consumidor do host mantinha a serial aberta na checagem seguinte. **Último estado observado: slim em RAM, `systemd=running`; não solicitei reinício para não interferir na outra sessão.**

Nenhuma gravação UFS, montagem de partição, mudança de clock/power domain ou teste de suspensão foi solicitado nesta coleta. Não foram testados escrita persistente, userdata completo, filesystem Arch, frequência física, autonomia ou recuperação completa. V2 permanece demonstrado; este ensaio não conclui V3/V7/V8 nem libera instalação do rootfs.
