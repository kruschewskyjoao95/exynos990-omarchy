# Som interno do SM-G780F (pesquisa, sem patch)

Marcações: **[obs]** observado no código/arquivos; **[rel]** relatado pelo autor do port ou terceiros; **[prop]** proposta nossa; **[teste]** testado no aparelho. Nada aqui é [teste].

## 1. Como o caminho de áudio é montado

- **[rel]** `sources/port/docs/STATUS.md:28`: áudio interno "not working", ABOX sem driver mainline.
- **[obs]** Placa: `sound { compatible = "samsung,picasso-prince" }` em `rt.dts:20636`, driver Samsung `sound/soc/samsung/picasso_prince.c` (2185 linhas). Rotas: `RECEIVER <- Left AMP SPK`, `SPEAKER <- Right AMP SPK`, `DMIC1<-MICBIAS1`, `DMIC2<-MICBIAS2`, mais BT (UAIF3), USB, FWD e VTS. `samsung,codec = <cs35l41@41, cs35l41@40, vts>`, prefixos `Left`, `Right`, `VTS`.
- **[obs]** Não há codec de áudio analógico. O **auricular (RECEIVER) é o amp cs35l41 @0x41 ("Left", `cs35l40-rcv`)** e o **alto-falante inferior é o cs35l41 @0x40 ("Right", `cs35l40-bot`, `cirrus,right-channel-amp`)**, ambos em `hsi2c@10680000` (i2c 9), reset por GPIO, sem IRQ útil. Revisão A0, ambos detectados no dmesg do Android (`dmesg.txt:4068,4070`). Comentário do `mixer_paths.xml`: "UAIF2 - Speaker/RCV AMP", "UAIF6 - DMIC through Serial LIF", UAIF3 = BT, UAIF0 = codec (não usado nesta placa).
- **[obs]** Cadeia de reprodução: app -> PCM `rdmaN` (ABOX RDMA, 12 nós `abox-rdma@18c51000..`) -> mixer/sifs/damper internos do firmware -> UAIF2 (I2S/TDM) -> cs35l41. O Android também liga um WDMA (wdma1, 4-5 canais) para trazer de volta o sinal de referência (VMON/IMON) dos amps ao DSP de proteção do ABOX/VSS.
- **[obs]** Captura: DMIC -> VTS (bloco de voz, `vts@0x15510000`, firmware `vts.bin`, DMIC e S_LIF/UAIF6) -> ABOX WDMA. DMICs ficam no bloco VTS (`reg-names "dmic","dmic1"`), não no ABOX diretamente. Clocks: `dmic`, `dmic_if`, `dmic_sync`, `rco`, `sysclk`. Há mailbox `samsung,mailbox-asoc @155a0000` entre AP e VTS.
- **[obs]** `abox@18c50000`: SFR 0x18c50000, sysreg 0x18c10000, SRAM 0x18d00000 (0x78c00), timer; 2 núcleos `abox-core` CA32 com power/enable/standby via PMU (offsets 0x3180/0x31a0..., 0x3200...), firmware `calliope_sram.bin`+`calliope_dram.bin` (core 0) e `_2` (core 1, offsets 0x32000/0x280000); IPC tx/rx em `0x850000/0x868000` (0x18000 cada), shm `0x8bc000`, handshake `0x2f2e0`; GIC próprio `abox-gic@18cf0000`; SysMMU `18e50000`; 5 clocks (pll, pll1, audif, bus, cnt); UAIF 0..6 + DSIF em `0x18c50500..`; PM QoS. Memória reservada: `abox-rmem` 0xf8000000/0x2a00000 (DRAM do firmware), `abox-dbg` 0x5600000, `abox-slog` 0x2800000, rdma-compr, pci-rmem [obs: `dmesg.txt:85-116`] — já reservadas no DT do Android; precisam existir no DT do port (conferir).
- **[obs]** Topologia ALSA: `abox_tplg.bin` (1,0 MB, gerado de `abox_tplg.conf`, 143 kB texto legível: tokens de ID/rate/width/ch por RDMA/WDMA). Carregada pelo kernel Samsung via `abox_tplg.c` (1433 linhas) com firmware loader; o `abox_tplg.conf` (texto) permite entender o formato sem decodificar o binário.
- **[obs]** Dmesg Android: probe do ABOX, carga de `calliope_sram.bin` e `_2` por fallback de ueventd (`dmesg.txt:4102-4106`), `abox_tplg.bin` (`5941`). O firmware calliope roda em dois Cortex-A32 do bloco de áudio.
- **[obs]** `mixer_paths.xml` (7122 linhas) é a "receita" de controles: para o amp: `DSP1 Firmware = Protection`, `DSP1 Preload Switch=1`, `PCM Source = DSP`, `DSP RX2 Source = ASPRX1`, `ASP TX1 Source = DSPTX1`, `ASP TX2 = VMON`/ASPRX1, Boost Enabled, VPBR (brown-out) ligado, `CPD Disable=1` no handset. Handset usa `PCM Source = ASP` (sem DSP) no `dev-handset` (obs: o auricular do mixer não passa pela proteção DSP; só speaker e speaker2 passam por `DSPTX1`).

## 2. Amplificadores no mainline

- **[obs]** `sound/soc/codecs/cs35l41{,-lib,-i2c}.c` existe no port (`SND_SOC_CS35L41=m`, `WM_ADSP`, `FW_CS_DSP` = m em `kernel.config`). Aceita `cirrus,cs35l41` e `cs35l40`. A porta I2C e a ASoC DAI (`cs35l41_set_dai_fmt`, `hw_params`) existem; controles do tipo `Left AMP Enable Switch` são do driver Samsung "Prince" e não são os nomes mainline (`Left DSP1 Preload Switch`, `... Firmware` existem via wm_adsp, mas "AMP Enable Switch"/"PCM Source" etc. precisam ser conferidos, [prop] não assumir).
- **[obs]** Propriedades do DT Samsung `cirrus,dsp-part-name`, `cirrus,right-channel-amp`, `cirrus,mfd-suffix`, `cirrus,bd-*`, `cirrus,classh-*`, `cirrus,pwr-params`, `cirrus,dsp-noise-gate-*`, `cirrus,hw-noise-gate-*`, `cirrus,gpio-config2` **não existem** no binding mainline (`cirrus,cs35l41.yaml`: boost-*, asp-sdout-hiz, gpioN-*). Mainline usa `cirrus,gpio2-*`; o resto é ignorado (class-H e noise gate ficariam em default do chip; checar se há default seguro). `cirrus,boost-peak-milliamp = 0x1004` (4100 mA) deve ser repassado.
- **[obs]** Nome do firmware: wm_adsp monta `<dir>/<part>-<fwf>-<fw>[-prefix].wmfw|bin` (`wm_adsp.c:747-755`), com `dsp->part = "cs35l41"` (`cs35l41.c:1089`). O vendor tem `cs35l40-bot-dsp1-spk-prot.wmfw/.bin` e `cs35l40-rcv-dsp1-spk-prot.wmfw/.bin` (mesmo tamanho: 31780 B / 4216 B por canal; `-calib.bin` 980 B). [prop] Renomear/symlink em `/lib/firmware/cirrus/` para o padrão que o log do wm_adsp pedir (primeiro teste: ler a mensagem "Failed to request firmware <...>"). O `.bin` é o arquivo de coeficientes (parâmetros do protetor), o `.wmfw` o programa do DSP do chip. Precisa conferir se o wmfw "cs35l40" tem IDs de algoritmo compatíveis com o cs_dsp mainline (provável, o cs35l41 é a mesma família; **não verificado**).
- **[rel]** Patch do z3s (família Exynos 9830) já habilita o cs35l41 "sem IRQ" no port (`0001-...z3s...patch`). Isso só prova o driver de chip, não de áudio.

## 3. Segurança: proteção e calibração

- **[obs]** O firmware `spk-prot` é o limitador térmico/excursão do alto-falante, rodando no DSP do cs35l41 com dados de V/I (VMON/IMON, `ASP TX2 = VMON`). Sem o firmware carregado e o caminho `PCM Source = DSP`, o amp amplifica direto o sinal do SoC: **risco real de dano ao alto-falante** (queima de bobina, sobreaquecimento) com volume alto. O DT também define `cirrus,pwr-target-temp` 0xe74 / 0xf3c (3700 / 3900 em °C*100? [obs no dmesg: "target temp = 3700, exit temp = 3600"] ) e `bd-max-temp`: parâmetros do daemon de potência Samsung que não existem no mainline.
- **[obs]** `cirrus_amps` no DT (`rt.dts:20631`, `cirrus,num-amps=2`) apenas liga os dois amps aos drivers MFD de calibração/bigdata/pwr da Samsung ("Prince"). O código desses drivers (`drivers/mfd/cs35l41`, `include/linux/mfd/cs35l41`) **não está no checkout parcial** disponível; local exato do arquivo de calibração: **não confirmado**. [rel/hipótese] Em aparelhos Samsung com cs35l41 costuma ficar um arquivo em `/efs` ou em `cirrus` (calibração de impedância/Rdc). O `-calib.bin` do vendor é calibração genérica do projeto, não do aparelho. O backup de `efs` (`sda1`, 20 MiB; também `cpefs`, `sec_efs`) deve existir antes de qualquer teste com alto-falante. Verificar `backups/` (não toquei).
- **[prop]** Regra: nenhum PCM ao alto-falante sem (a) firmware prot carregado e confirmado no log, (b) volume digital limitado (-30 dB ou pior) no primeiro teste, (c) tom curto, mão no botão de desligar. O auricular (cs35l41 @0x41, `dev-handset`) em volume baixo é o alvo mais seguro, mas também é um amp com `PCM Source=ASP` (sem DSP) no mixer; mesmo assim carregar o prot do `rcv`.

## 4. Driver ABOX (LineageOS 4.19, 33 306 linhas, checkout `lk/k`)

Linhas por arquivo (`wc -l`): abox.c 3454, abox_cmpnt.c 6364, abox_soc.c 2736 (+ headers soc_2/3/21 3178), abox_rdma.c 2517, abox_dma.c 1787, abox_tplg.c 1433, abox_if.c 1091, abox_wdma.c 1059, abox_dump 888, abox_dbg 878, abox_vdma 855, abox_core 611, abox_log 454, abox_gic 399, abox_qos 381, abox_effect 310, abox_ipc 308, abox_util 278, abox_adaptation 249, abox_ion 230, abox_pci 227, abox_msg 217, abox_failsafe 160, abox_vss 136, abox_shm 68. VTS: `sound/soc/samsung/vts` 8334 (c) + headers.

**Essencial para tocar PCM simples (proposta [prop], baseada na leitura dos nomes e do Makefile, não em execução):**
- `abox.c`: probe, clocks, sysmmu/IOMMU map da DRAM do firmware, carga de firmware, power sequence, IRQ do GIC do ABOX, handshake. (~3,5k; reescrever núcleo ~1,2k)
- `abox_core.c` (611): liga/desliga os A32 via PMU (`pmu_power/enable/standby`) e copia calliope sram/dram. Precisa de regmap PMU e SRAM mapeada.
- `abox_gic.c` (399) + `abox_ipc.c` (308) + `abox_msg.c` (217) + `abox_shm.c` (68): mensageria AP<->firmware (IPC tx/rx areas, IRQ). **Protocolo é só conhecido pelo código Samsung**; é a maior incógnita.
- `abox_rdma.c` (2517, sem compressão ~1,5k), `abox_dma.c` (1787, base), `abox_if.c` (1091: UAIF/DSIF, clocks, formato I2S/TDM), `abox_soc.c` (2736, registradores e clocks por SoC; usar só o subconjunto do soc_3 que corresponde ao 990), `abox_cmpnt.c` (6364: widgets/controles DAPM de mixers SIFS/NSRC/damper/UAIF; usar só os mínimos de rota ou reduzir à topologia estática), `abox_tplg.c` (1433, carga de `abox_tplg.bin`, opcional se rotas fixas em C), `abox_util`, `abox_qos` (ligações de PM QoS opcionais; o firmware pode exigir um piso de freq).
- Capturas: `abox_wdma.c` (1059) + VTS (`vts.c`, `vts_s_lif*`, `vts_dma`, `mailbox.c`, ~3-4k úteis).

**Opcional/ignorável na primeira versão:** `abox_effect`, `abox_vss`/VSS (voz/modem), `abox_dbg`, `abox_dump`, `abox_log`, `abox_failsafe`, `abox_ion`, `abox_pci`, `abox_adaptation`, `abox_vdma`, compressão (`abox-rdma-compr`), dual/ddma, DisplayPort audio, QoS (começar com clock fixo).

**Estimativa [prop]:** núcleo mínimo para um PCM de reprodução (probe + core + IPC + GIC + 1 RDMA + UAIF2 + rotas fixas, sem tplg) ≈ **6-8 mil linhas** adaptadas/limpas (vs 21 mil das partes não opcionais). Captura DMIC via VTS acrescenta ≈ 3-4 mil. Esforço grosseiro: **semanas** só com porta direta para o kernel 6.12 (a API ASoC mudou: DAI/componentes, `snd_soc_dapm`, iommu, clk, regmap, PMU), mais depuração cega porque o firmware calliope é binário fechado e não há console do DSP além do `abox_log` em rmem. Primeiro marco realista: firmware boot + handshake + 1 buffer circulando, sem som. Risco de não funcionar sem o protocolo exato.

## 5. Trabalho público de ABOX mainline

- **[rel]** Existe série de Samsung (ew.kim) de julho/2025 para ExynosAuto v920: "Add ExynosAuto ABOX generic platform and PCM support" (driver genérico de gerência ABOX, IPC e PCM) em revisão no linux-arm-kernel/linux-samsung-soc; **sem evidência de merge** e para SoC automotivo, outro firmware e interface. Fontes: https://lists.infradead.org/pipermail/linux-arm-kernel/2025-July/1046572.html , https://lists.infradead.org/pipermail/linux-arm-kernel/2025-July/1046578.html , https://patchew.org/linux/20250709001002.378246-1-ew.kim@samsung.com .
- Busca por postmarketOS/exynos990/Exynos 9810/9820/2100 não achou ABOX mainline para celular. A ausência na busca não prova inexistência. Não acessei o git do mainline atual. [prop] Vale ler essa série (provavelmente documenta o protocolo IPC genérico, parecido com o do Exynos 990) e verificar em kernel.org se foi aceita.

## 6. Caminho mínimo viável [prop]

0. Dia 0 (só leitura): `.config` do port, ver se DT do port já inclui nós `abox` ou reserva de memória; checar ausência de `sound`/`cs35l41` no `exynos990-r8s.dts`.
1. **Provar o amp sem ABOX**: DT `cs35l41@40/41` mainline com `reset-gpios`, VA/VP, `cirrus,boost-peak-milliamp`; só **probe I2C e leitura de REVID**, sem áudio e sem habilitar amp (consegue-se também sem ABOX). Teste de risco ~zero.
2. **Primeira prova de áudio: captura DMIC** (nenhum amp, nenhum risco de dano): subir VTS + mailbox e ABOX o mínimo para gravar do DMIC1 via WDMA/S_LIF. Alternativa: capturar o DMIC direto pelo bloco VTS sem ABOX, se o `vts.bin` rodar sozinho (hipótese, **não confirmada**: o VTS roda DSP próprio, mas usa o mailbox e o ABOX para entregar PCM).
3. Reprodução no **auricular** (amp rcv) com firmware prot do rcv carregado e volume mínimo.
4. Alto-falante com firmware prot do bot, mais calibração.
5. Depois: tplg/PipeWire (UCM2), mixers de rota via `alsaucm`.

## 7. Riscos

- Dano de alto-falante sem prot/calibração (seção 3). Dano a amp por boost mal configurado (`boost-peak`, VP). Hang no boot ao ligar PMU/clock do ABOX com IOMMU/rmem erradas (o aparelho só volta desligando). Protocolo IPC do calliope só em fonte Samsung (GPL, adaptável com atribuição); firmware **não** vai ao git.
- O DT do Android reserva `abox-rmem` etc. em endereços específicos (`dd600000`, `d8000000`, `f4200000`, `f7fb0000`, `f8000000`); o DT do port tem outro mapa de memória (`0003-...8GB-memory-map`): conferir conflitos antes de reservar.

## 8. Alternativas imediatas

- **Fone/headset/DAC USB-C** (UAC, host USB já funciona no port): zero driver novo, PipeWire/ALSA padrão. Melhor primeira solução de som. Observação: fone USB-C com microfone dá captura também.
- **Bluetooth A2DP** quando o BT funcionar (chip QCA/ROME segundo `roadmap/07`; áudio por HCI, não passa pelo ABOX).
- Já existente: null sink PipeWire + loopback (`STATUS.md`) só mantém apps rodando.
- LineageOS/Halium: o HAL de áudio fica sobre o mesmo driver ABOX do 4.19; não elimina o trabalho no kernel (só serve para mapear rotas).

## 9. Perguntas em aberto

1. Onde exatamente fica a calibração do amp no Android (código `mfd/cs35l41/calibration.c` ausente do checkout)? Buscar no repo `android_kernel_samsung_universal9830` do LineageOS.
2. O `.wmfw` "cs35l40" carrega no cs_dsp mainline?
3. Existe backup de `efs`/`cpefs` em `backups/`?
4. O VTS/DMIC captura sem ABOX completo?
5. Protocolo IPC do calliope vs. série ExynosAuto de 2025?
