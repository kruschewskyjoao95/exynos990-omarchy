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

## Próximo passo

Medir o LineageOS em execução neste aparelho, com a câmera aberta: os registradores do PHY em `0x170D1300..0x170D17FF`, o bias em `0x170D1000`, `CSIS0` e `sysreg 0x17020500`. Depois, comparar com o #10 palavra por palavra. O código-fonte não mostra mais nenhuma diferença.
