# Avisos de UFS e clocks no baseline

Data: 2026-11-17. Kernel em execução: `6.12.0-rc5-next-20241104-r8s #1 SMP PREEMPT Tue Nov 17 15:41:42 UTC 2026`, o mesmo carimbo do slim do baseline. Coleta pelo console USB do `r8s-slim`, com o root em RAM. Nenhum `mount` de `/dev/sd*` ou UFS. Nenhum flash nesta coleta. Logs: `logs/m2-ufs-dmesg.log`, `logs/m2-ufs-sysfs.log`, `logs/m2-clocks-dmesg.log`, `logs/m2-clocks-sysfs.log`.

Linhas citadas abaixo foram lidas em `out/work/linux`, a árvore que produziu esse kernel.

## UFS: os quatro `dme-set` não impedem o link

**[testado neste aparelho]** O dmesg desta sessão, logo depois dos quatro erros, registra:

`Power mode changed to : FAST series_B G_3 L_2`

O sysfs confirma o mesmo estado, ainda ativo na hora da leitura: `HS_GEAR3`, 2 pistas, `HS_RATE_B`, `FAST_MODE`, `link_state=ACTIVE`. O chip responde como `SAMSUNG KLUDG4UHDB-B2D1` revisão `0090`, especificação `0x0310` (UFS 3.1), 5 LUNs (`sda`–`sde`). `sda` tem 119,1 G e `ro=0`; `sdb`–`sde` estão `ro=1`. `capabilities/clock_scaling` é `0`.

**[código]** A mensagem sai de `ufshcd_dme_set_attr()` (`drivers/ufs/core/ufshcd.c`). `failed 0 retries` significa uma tentativa só: o atributo é local, então o laço de retentativa do peer não corre. Os quatro ids desta sessão são um par:

| Ordem | attr | valor | Quem chama |
| --- | --- | --- | --- |
| 1 | `0x9540` `PA_DBG_OV_TM` | 1 | `exynos_ufs_enable_ov_tm()` |
| 2 e 3 | `0x0321` `RX_SYNC_MASK_LENGTH` | `0xd` | uma vez por pista RX |
| 4 | `0x9540` | 0 | `exynos_ufs_disable_ov_tm()` |

Isso é `exynos_ufs_config_sync_pattern_mask()` (`drivers/ufs/host/ufs-exynos.c`), chamada em `exynos_ufs_pre_pwr_mode()` quando o modo pedido é HS. A função é `void` e ignora o retorno do `ufshcd_dme_set`. O `0xd` é a máscara calculada (`calc_time_cntr` do sync de G3, deslocada 8 bits); o comando que a gravaria é que falhou.

**[código]** O próprio driver do 990 já trata outro DME do mesmo jeito. O comentário de `exynos990_uic_attr` diz que o 990 rejeita `PA_DBG_CLK_PERIOD` (`0x9514`) por DME e que esse offset foi zerado de propósito; a escrita vai por registrador em `exynos990_ufs_pre_link()`. `PA_DBG_OV_TM` ficou de fora dessa exceção. O log `DBG pre_link mclk=166562500` é essa função e mostra que o prelink rodou.

**[código]** Os relógios que o controlador usa não vêm do CMU. Em `exynos990.dtsi`, `ufs@13100000` aponta `core_clk` e `sclk_unipro_main` para o mesmo `fixed-clock` `ufs-core-clock` de 166.562.500 Hz, com `freq-table-hz = <0 0>, <0 0>`. No aparelho esse clock tem enable 2 e essa taxa. O `dout_cmu_hsi1_ufs_embd` aparece no `clk_summary` a 133.250.000 Hz, enable 0, sem consumidor. O driver não o liga.

Os avisos `vdd-hba` / `vccq` / `vccq2` são o `ufshcd_populate_vreg` assumindo o trilho já ligado. O `ufs-vcc` do DT está como supplier (`regulator-ufs-vcc`). Não houve mensagem de link down depois disso.

## Leitura, sem montar

**[testado neste aparelho]** `/proc/mounts` não tinha `sd` nem `ufs` antes nem depois. Três `dd` de leitura:

- 512 bytes de `/dev/sda`: `ba3a332993b368d7289c088eb49e072afccdd33383f410d06015789eebde8b45`
- 2 MiB de `/dev/sda13`: `2b78921651a47e1f3f190df07ffc3c544323e0083d57cc1abb54a4effac8082a` (o mesmo hash do mapa lk3rd da sessão anterior)
- 4 KiB de `/dev/sda33` (`bs=512 count=8`): `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7`, SHA-256 de 4096 bytes zero.
- A coleta anterior em `logs/m2-ufs-read.log` leu 1 MiB (`bs=512 count=2048`) e obteve `30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58`, SHA-256 de 1 MiB de zeros. São o mesmo conteúdo em dois comprimentos. O começo do slot `boot` está zerado; o restante dos 57 MiB não foi lido aqui.

O contador em `monitor/` ficou em zero para leitura e escrita. Ele também não subiu com esses `dd`, então não serve de prova de I/O. A prova é o hash voltando do aparelho. `auto_hibern8` devolveu `EOPNOTSUPP`.

`geometry_descriptor/raw_device_capacity` = `0xEE64000` unidades de 512 bytes = 127.999.672.320 bytes, na mesma ordem do `sda` de 119,1 G.

`health_descriptor`: `eol_info=0x01`, `life_time_estimation_a=0x0B`, `life_time_estimation_b=0x0B` (reproduzido em boot novo de `r8s-ram.img` 63.150.080 B hash `fe07490f…` + releitura serial `logs/m2-ufs-health.log`). O sysfs imprime o byte cru (`0x%02X` em `ufs_sysfs_read_desc_param`) com query fresca por leitura (sem cache), offsets 2/3/4 do descritor Health — o layout bate com o JEDEC (0=length, 1=type, 2=EOL, 3=A, 4=B), então não há bug visível de decode nem leitura de descritor errado.

Segundo o JEDEC/MS: `eol_info 0x01` = normal (<80% dos blocos reservados consumidos) e `life_time 0x0B` = excedeu a vida estimada (= ciclos P/E, cálculo vendor-specific). São contadores diferentes, mas `0x0B` nas duas estimativas com `eol` zerado é contraditório o bastante para exigir confirmação independente antes de instalação persistente (item já aberto no quadro para Recovery/Android, com o `[codex]` cruzando o log Samsung).

**Como resolver (o que software não faz):** nenhum patch do kernel corrige desgaste físico — os fixes 0107 só silenciam `dme-set`/clocks, não a vida útil. Opções reais: (1) mitigar — RAM-first (sem gravar `userdata`), backup externo frequente, carga de escrita mínima; (2) confirmar — ler o mesmo descritor no Recovery/Android (pilha independente) para separar chip gasto de encoding Samsung; (3) aceitar o risco com retorno ao stock pelo Download mode (já preparado), sem declarar o chip morto por um byte. Sem prova de leitura independente, não instalar rootfs persistente como se o chip fosse novo.

## Clocks: três avisos, três origens

**[código + testado]** `clk: Not disabling unused clocks` é `clk_disable_unused()` em `drivers/clk/clk.c` quando a cmdline tem `clk_ignore_unused`. A cmdline deste boot tem esse parâmetro. É o aviso de que a opção pegou, não uma falha de árvore.

**[código + testado]** `exynos990-cmu 18c00000` é o `cmu_aud` (`compatible = "samsung,exynos990-cmu-aud"`, `power-domains = <&pd_aud>`, `exynos990.dtsi`). Em `exynos990-r8s.dts`, `&pd_aud { status = "disabled"; }`: o comentário da placa diz que, no suspend, o SMC do TZPC (`samsung,need-smc`) levanta SError. Com o domínio desligado, `__genpd_dev_pm_attach()` não acha o provider e chama `driver_deferred_probe_check_state()`, que depois do prazo devolve `-ETIMEDOUT` (`-110`) e imprime `deferred probe timeout, ignoring dependency`. Isso não é um timeout medido ao energizar AUD. O comentário do `dtsi` (o poll do `exynos-pd` estoura se o PMU não conseguir ligar o domínio) descreve outro caminho, que este boot não percorreu: o DT vivo está `disabled` (`logs/m2-clocks-native.log`). No aparelho, `exynos990-cmu` só tem ligado o `10a00000` (HSI0). O `18c00000` não tem symlink `driver`. `dout_cmu_aud_cpu` fica a 800 MHz, enable 0, sem consumidor. O UFS não usa esse CMU.

**[código + testado]** `exynos-clkout` retorna `-22` (`-EINVAL`) em `exynos_clkout_match_parent_dev()` (`drivers/clk/samsung/clk-exynos-clkout.c`). A tabela só lista `samsung,exynos5410-pmu`, `samsung,exynos5420-pmu` e `samsung,exynos5433-pmu`. O pai no DT é `system-controller@11860000`, com `compatible = "samsung,exynos850-pmu", "syscon"` e `reg = <0x15860000 0x10000>` (`exynos990.dtsi`). O endereço do nó não é a base MMIO. O console leu esses dois compatibles em `logs/m2-clocks-native.log`. Nenhum dispositivo ficou em `exynos-clkout`. É o mux de debug CLKOUT, não o relógio do UFS.

## O que isso libera e o que não libera

Nesta sessão a enumeração e as leituras curtas aconteceram com os quatro `dme-set` no log. A máscara de sync não foi aplicada: o `ufshcd_dme_set` que a gravaria falhou e o chamador ignorou o retorno. Isso não aprova escrita, `mount`, troca de power-mode nem carga longa. Gravar o rootfs continua pendente de um ensaio próprio. O `-110` do `cmu_aud` é o efeito de deixar `pd_aud` desligado; religar o domínio é o caminho do SError que o DTS já recusou. Silenciar o `PA_DBG_OV_TM` no 990, no mesmo estilo do `PA_DBG_CLK_PERIOD`, seria só para limpar o log: o retorno já é ignorado e o modo de energia seguinte foi aceito. As seis leituras de recovery/DTBO que bateram com os backups estão na coleta independente [ufs-clocks-codex.md](ufs-clocks-codex.md); esta sessão não as repetiu.
