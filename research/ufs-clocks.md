# Avisos UFS/clocks no baseline (slim em RAM, 17/11/2026)

Coleta somente leitura no slim (`r8s-ram.img`, sem flash, sem montagem UFS): dmesg, `/sys/kernel/debug/clk/` (debugfs já montado), `lsblk` e `dd` de leitura. Logs brutos em `logs/m2-{clocks,ufs}-*.log` (fora do Git, como os anteriores de M2). Origem rastreada no kernel fixado (`out/work/linux`, `6.12.0-rc5-next-20241104-r8s`).

## UFS: `dme-set` falhando em debug, link OK

Avisos (4×, `exynos-ufshc 13100000.ufs`, ~0,41s): `attr-id 0x9540` val `0x1`/`0x0` e `attr-id 0x321` val `0xd` (2×), todos `failed 0 retries`. Depois: `Power mode changed to FAST series_B G_3 L_2`, e as leituras passaram (`sda13` `2b789216…` = região lk3rd pós-boot, `sda33` `30e14955…`).

- `0x9540` é `PA_DBG_OV_TM` (`drivers/ufs/host/ufs-exynos.h`): debug que habilita override de timer em volta de `dme-set` — `exynos_ufs_enable_ov_tm`/`disable_ov_tm` (`ufs-exynos.h:270`, chamado em `ufs-exynos.c` antes/depois de cada lote de MIBs, incluindo o de sync).
- `0x321` é `RX_SYNC_MASK_LENGTH` (`ufs-exynos.h:95`): escrita por lane em `exynos_ufs_config_sync_pattern_mask` (`ufs-exynos.c:760`) com máscara calculada para 20 µs em G3 — entre o enable e o disable do `OV_TM` acima.
- `failed 0 retries` é o comportamento do `ufshcd_dme_set_attr` (`core/ufshcd.c:4117`): o loop só retenta quando `peer` (DME_PEER_SET); para DME_SET local falha na 1ª tentativa e devolve `UFS_UIC_COMMAND_RETRIES - retries` = 0. Não é falta de tentativas de link — o link veio em seguida.
- Leitura: o PHY recusou as duas escritas de debug/sync, mas o bring-up de link (GEAR 3, 2 lanes) concluiu e a leitura em disco passou. São avisos de debug best-effort, não erro de link — mas a máscara de sync não foi aplicada, então a sincronização de modo de energia não tem a máscara programada.

## Clocks: 3 avisos esperados em bring-up

- `exynos-clkout: cannot match parent device` / probe `-22`: `clk-exynos-clkout.c` só casa PMUs 5410/5420/5433; o DTS r8s traz `samsung,exynos850-pmu`. Sem suporte a 990 — inofensivo em slim (clkout de debug).
- `exynos990-cmu 18c00000` timeout `-110`: `18c00000` é o `cmu_aud` (`compatible = samsung,exynos990-cmu-aud`, `exynos990.dtsi:527`), dentro do PD `pd_aud` (SMC `0x18e10204`). O próprio DTS avisa: se o PMU não energiza, `cmu_aud` falha “gracefully”. Áudio fora do escopo do slim; o resto dos clocks do CMU_TOP foi registrado (`clk_summary` 400/800 MHz).
- `clk: Not disabling unused clocks`: cmdline traz `clk_ignore_unused` (visível no dmesg) — intencional para bring-up (`clk.c:1517`). Órfãos: `mout/gout/dout_cmu_core_bus` e `dout_cmu_shared1_div4` (rate 0, deviceless).

## Veredito

Nenhum aviso impede o boot slim ou a leitura UFS; nenhum dos três grupos é erro de hardware: são (a) writes de debug recusados pelo PHY com link OK, (b) drivers de audio/clkout sem suporte no DTS, (c) não-desligar clocks por cmdline intencional. Reavaliação pendente antes do rootfs: se o sync mask importar para power-mode do Arch/Omarchy — fora do escopo desta coleta (só leitura).

*Não testado: escrita UFS, montagens, GeAR >3, DVFS da GPU e áudio.*
