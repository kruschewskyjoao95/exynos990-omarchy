# Câmera traseira: diagnóstico 0128–0129

Testado neste aparelho em 19/11/2026, via SSH, salvo onde indicado. Os bits foram decodificados pela SFR do LineageOS `sensor/csi2/is-hw-csi-v5_3.h` (árvore `97369af7`).

## Kernel #9 (0128)

- `v4l2-ctl` devolveu 1 quadro de 3.822.336 B, todos zero. A captura de 5 quadros ficou parada, com um único FRM_END.
- O WDMA terminou com `dma_int=0x01110011` (LINE_END, FRM_START, ABORT_DONE, OTF_OVERLAP e FRAME_DROP no ch0) e `DMA0_ACT_CTRL=0x10000` (ACTIVE_DMA_N_ABORTED).
- `pattern=1` (gerador interno do WDMA, sem sensor nem PHY) gravou 2 quadros, com 4.572.288 bytes não nulos de 7.644.672. **O caminho WDMA→RAM funciona**, o que descarta SysMMU e S2MPU.
- O barramento CSIS está a 533 MHz (`dout_cmu_shared0_div4`, `clk_summary`). O DVFS ACPM do 0125 devolve `set=0`, que é sucesso. Só o `get_rate` volta 0.

## Kernel #10 (0129, `052c6d80…`)

O 0129 expõe parâmetros que valem a cada stream-on: `phy_exynos990_mipi_csi.{lineage_reset,settle}` e `exynos990_csis.potf`. O roteiro de varredura ficou no scratchpad da sessão. Cada linha corresponde a uma captura de 2 quadros, com `timeout 10`.

| lineage_reset | potf | settle | vc0_frames | int0 | resultado |
|---|---|---|---|---|---|
| 0 | 0 | 7 | 1 | `0x1b` | FS sem FE, trava |
| 1 | 0 | 7 | 1 | `0x1b` | FS sem FE, trava |
| 0 | 1 | 7 | 406 | `0xf000001b` | lost FS/FE, VRESOL |
| 1 | 1 | 7 | 1390 | `0xf000001b` | idem, `phy_st=0x81` |
| 0 | 1 | 3 | 9491 | `0xf000001b` | idem |
| 0 | 1 | 5 | 4382 | `0xf000001b` | idem |
| 0 | 1 | 6 | 3052 | `0xf000001b` | idem |
| 0 | 1 | 8 | 5194 | `0xf000001b` | idem |
| 0 | 1 | 9 | 1345 | `0xf000001b` | idem |
| 0 | 1 | 11 | 867 | `0xf077005b` | aparecem erros SOT |
| 0 | 1 | 14 | 171 | `0xf060005b` | 1.011 bytes não nulos no buffer |

`int0` bits 0, 1, 3 e 4 correspondem a ERR_ID, ERR_CRC, ERR_WRONG_CFG e ERR_OVER.

## Leitura

- **OTF (`potf=0`) exige consumidor.** Sem 3AA ou ISP, o CSIS para após o primeiro FS. Para captura só por DMA, use `potf=1`. Os patches 0124 e 0128 alternaram essa escolha.
- **O enlace C-PHY entrega pacotes corrompidos** em todas as combinações: ERR_ID e ERR_CRC já desde o primeiro quadro, e FS espúrios aos milhares por segundo. Com o sensor a 30 fps, o esperado seria cerca de 300 em 10 s. O estouro da FIFO (ERR_OVER) e o abort do WDMA são consequência disso. O conjunto de erros é o mesmo a 88,8 MHz (#5) e a 533 MHz (#9).
- A ordem do reset do PHY não muda o resultado. O settle muda, mas nenhum valor limpa o enlace, e com 11 ou mais aparecem erros de SOT.
- Já conferido igual ao LineageOS no código, sem efeito no resultado:
  - os valores analógicos do DCPHY 0503_0000 em modo C;
  - o settle da tabela de 7 nm;
  - o PLL do sensor (`0x0310=0x156`, "2964 Msps");
  - o endereço, a isolação e o reset do PHY;
  - as fontes LDO5S e LDO6S;
  - `CMN_CTRL` (3 trios, VC_DT, sem descramble), `PHY_CMN_CTRL=0x1f`, LRTE e PACKED_PIXEL_MODE.

## Sensor, MCLK e alimentação (kernels #10 e #11, 0130 `aae90d01…`)

Leitura durante a captura, com `potf=1` e settle 7:

- **MCLK:** `dout_cmu_cis_clk0` = 26.000.000 Hz, habilitado por `1-0010`, segundo o `clk_summary`.
- **Sensor:** o contador de quadros (`0x0005`, lido por I2C) foi de 76 a 106 e a 137, com 1 s entre leituras. São **30 fps reais**. `0x0100=1`, PLL `0x156`, FLL `0x5824`, LLP `0x08e0`.
- **CSIS no mesmo ensaio:** `vc0_frames=1820` em ~7 s (~260/s), cerca de 8,5 FS por quadro real. O único buffer entregue tinha dados só na linha 0 (2.009 bytes).
- **PMIC (0130):** LDO5S `ctrl=0xcc` e LDO6S `ctrl=0xec`. Estão ligados e com `vsel` 0x0C (0,85 V) e 0x2C (1,8 V), já ajustados pelo bootloader.
- **Ordem das fontes do PHY (0,85 V → 1 ms → 1,8 V):** três ensaios, mesmo padrão de erro (`vc0_frames` 573, 2236 e 5894; `int0=0xf000001b`).

Ficam descartados como causa: a taxa e o MCLK do sensor, a tensão dos trilhos do PHY e a ordem de ligar as fontes.

## Leitura de volta durante o stream (kernel #11, `/dev/mem` e I2C)

- **Sensor (CCS):** `0x0100=01`, `0x0111=02`, `0x0112=0a0a` (RAW10), `0x0114=02` (3 lanes), `0x0600=0000` (sem test pattern), `0x0BCC=0100`. O setfile do LineageOS também não grava `0x0111`. Ele grava `0x0114=0x0201`, igual ao nosso. A seleção C-PHY é do fabricante.
- **PHY:**
  - O bias `0x170D1000` vale `10/110/3223/40`.
  - Os trios SD0–SD2 (`0x170D1400/1500/1600`) valem `GNR_CON0=3`, `0x1450`, `9`, `82c8`, `1`, `8680`, `4000`, `200`, `638`, `40`, TIME `7`/`32`, DESKEW `0` e CRC `1503`/`33`.
  - Tudo igual ao `__set_phy_cfg_0503_0000_dcphy` em modo C, ou seja, as escritas **ficam** no hardware.
- **CSIS0:**
  - `CMN_CTRL=0x00204e01` (PHY_SEL C-PHY, 3 trios, VC_DT, CSI_EN, deskew 2) e `CLK_CTRL=0x10`.
  - Configuração dos canais: CH0 `0x28ac`/`0x05e807e0`, CH1 `0x128ac`/`0x017a07e0` e CH3 `0x2848`/`0x000207e0`.
  - `LRTE=0x80000000`, `DBG_OPTION=0x00800000` e `PHY_CMN_CTRL=0x1f`.
- **SYSREG_CSIS `0x17020000`:** `0x404=1`, `0x408=0`, `0x41c=0` (DMA2←CSIS0), `0x440=0`, `0x448=0`, `0x450=0x3fe00`, `0x454=0x1ff` e `0x500=1`. São todos os valores de reset da tabela Samsung (`is-v8_0_0/is-hw-chain.c`).

Toda a configuração visível no código Samsung está confirmada no hardware. O que resta é algo que o código não mostra: um estado deixado pelo firmware ou pelo HAL no LineageOS, ou uma diferença física.

## Próximo passo

Medir o LineageOS em execução neste aparelho, com a câmera aberta: os registradores do PHY em `0x170D1300..0x170D17FF`, o bias em `0x170D1000`, `CSIS0` e `sysreg 0x17020500`. Depois, comparar com o #10 palavra por palavra. O código-fonte não mostra mais nenhuma diferença.

## Ordem de início sensor/CSIS (kernel #12, 0131 `a1040394…`)

O 0131 expõe dois parâmetros: `order` (0 = A: CSIS/PHY → atraso → sensor; 1 = B: sensor → atraso → CSIS/PHY; 2 = C: CSIS/PHY → sensor → atraso → sensor desliga e religa) e `delay_ms`, com os valores 0, 1, 5, 10 e 50. Foram 15 ensaios, com `potf=1` e settle 7.

- Todos os 15 mostram `int0=0xf000001b` e `vc0_frames` entre 600 e 12.956, ou seja, FS falsos.
- Quatro entregaram um buffer: A/0, A/10, B/5 e B/10. Nos quatro só a **linha 0** tinha dados, entre 1.025 e 2.004 bytes, como já ocorria antes.
- Nenhum quadro saiu limpo, e a variação entre os ensaios é aleatória.
- Antes da primeira escrita, o PHY lê **tudo zero** (bias e SD0): não há estado deixado por firmware ou bootloader.

Descartados: ordem e atraso entre o sensor e o receptor, e estado prévio do PHY.
