# Correções UFS / CMU_AUD / CLKOUT — 17/11/2026

Implementação: `packaging/kernel-patches/0107-r8s-ufs-sync-and-unavailable-clocks.patch`, aplicado pela receita tanto no baseline quanto na série experimental. Base e reprodução física: [investigação independente](ufs-clocks-codex.md). Atualização: **patch executado em RAM no telefone**, três achados ausentes e seis leituras diretas aprovadas; [resultado físico e limitações](../checks/ufs-clocks-ram.md). As seções abaixo descrevem o build inicial, anterior ao empacotamento/teste físico.

## Mudanças

- **UFS:** nova opção `EXYNOS_UFS_OPT_SKIP_SYNC_PATTERN_MASK`, habilitada somente em `exynos990_ufs_drvs`. A função de máscara retorna sem tentar o lote `PA_DBG_OV_TM → RX_SYNC_MASK_LENGTH × lanes → PA_DBG_OV_TM` que este aparelho rejeitou. A calibração específica da PHY, a negociação HS e os demais comandos permanecem no caminho original. Outros Exynos mantêm a sequência. É um quirk para evitar programação incompatível; não implementa uma máscara alternativa, não comprova os valores que o hardware manteve e não aumenta a vida útil da memória. Não foram removidos logs de erro do core UFS.
- **Áudio:** o DTS r8s desabilita `cmu_aud` junto de `pd_aud`. O consumidor deixa de aguardar um provider deliberadamente ausente. Não liga o domínio nem toca na sequência TZPC que motivou sua desativação. Não acrescenta suporte de áudio.
- **CLKOUT:** o probe da PMU não instancia o filho MFD `exynos-clkout` quando o pai usa `samsung,exynos850-pmu`, compatible usado pelo r8s e ausente da tabela do driver CLKOUT. Inicialização/regmap da PMU e população dos filhos OF, incluindo poweroff, continuam executando. As outras variantes mantêm a criação do filho. Não se inventa compatible nem programação MMIO para CLKOUT.

## Validação realizada

- `python3 checks/test-build-recipes.py`: **17/17**; fixtures atualizadas para a seleção real do patch no baseline e na série.
- `python3 checks/test-kernel-sets.py`: **3/3**.
- `python3 checks/test-ufs-clocks.py`: **3/3**. A mesma verificação contra `out/work/linux` antigo falhou nos três achados. O teste compila/executa a função UFS extraída da fonte com um harness C: gears 1–4, quirk ligado/desligado, ordem dos comandos e seleção exclusiva da variante Exynos990. Também inspeciona AUD/provider no DTB compilado e preservação dos filhos OF da PMU.
- Aplicação de 0102–0105 seguida de 0107 sobre baseline em diretório temporário: sem conflitos.
- `checkpatch.pl --no-tree --no-signoff`: **0 erros / 0 avisos**. Não foi criada certificação Signed-off-by para submissão upstream.
- Build AArch64 em `r8s-kbuild:trixie`: objetos UFS/PMU e depois **Image, módulos e DTBs completos**, com instalação dos módulos em staging isolado. Logs locais: `logs/ufs-clocks-build.log`, `logs/ufs-clocks-full-build.log`. Checksums relativos em `out/validation/ufs-clocks/boot/SHA256SUMS`.

| Artefato isolado | SHA-256 |
| --- | --- |
| `out/validation/ufs-clocks/boot/Image` | `414e655c5879acb648c46ffed1c5e4184207cbf8870043b2292f4a27f64476c1` |
| `out/validation/ufs-clocks/boot/exynos990-r8s.dtb` | `96bd4311189a0fdc0864272b21d97ca45f077e5638da4d580ed79e302d0f6899` |
| `out/validation/ufs-clocks/boot/.config` | `e59176c00e4764f8ebb5c3157f62bd4f7a37d58babb70bb0dea09e9666be7b18` |

## Limites e próximo teste

Nenhum comando USB, flash, montagem UFS, escrita, mudança de power-mode ou reboot do telefone nesta implementação. Os artefatos conhecidos em `out/boot/` continuam sendo o baseline anterior, sem 0107; hashes conferidos após o build. Não misturar o kernel novo com initramfs/rootfs/módulos de outra compilação, mesmo com `kernelrelease` igual. Antes de boot físico, regenerar e verificar o conjunto de diagnóstico RAM com os artefatos novos; este diretório isolado ainda não contém uma nova imagem Android/uniLoader empacotada.

No ensaio em RAM, verificar ausência dos quatro erros de configuração e dos probes CLKOUT/AUD indevidos, negociação UFS G3/2 lanes, console, PMU/poweroff, contadores e leituras diretas comparadas aos backups. Escrita persistente e suspensão exigem ensaios próprios. Não declarar validação física a partir deste build.

Saúde: os valores previamente reportados `life_time_estimation_a/b=0x0B` precisam de confirmação independente antes da instalação persistente. Pre-EOL e estimativa de vida medem aspectos diferentes, portanto `eol_info=0x01` não invalida automaticamente o alerta de desgaste. Essas correções de software não corrigem desgaste físico.

Atualização: [confirmação independente encontrada no log Samsung preservado](ufs-health.md), anterior aos testes nativos: `LT: 0xbb`. O indicador não foi introduzido pelo patch 0107; a limitação física permanece.
