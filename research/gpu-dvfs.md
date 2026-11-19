# DVFS da GPU (Mali-G77 / Panfrost) — agente `gpu-dvfs`

Patch: `packaging/kernel-patches/0102-gpu-dvfs-g3d-acpm-clock-opt-in-devfreq.patch`
(branch `feat/gpu-dvfs`, commit `1058ae9c`, sobre `r8s-port-base`). **Nada foi testado no aparelho.**

## O que o código Samsung faz (observado no código, LineageOS `97369af7`)

- ID: `acpm_dvfs_exynos9830.h` → `MIF=0 … CP=9, G3D=10`, com `ACPM_VCLK_TYPE = 0x0B040000`.
  O DT real do aparelho (`rt.dts`, nó `mali@18500000`) tem `g3d_cmu_cal_id = <0xb04000a>`,
  ou seja, índice **10**. O dmesg do kernel Samsung no aparelho mostra `dvfs_type : G3D - id : a`
  (observado no log do aparelho).
- Chamada: `gpexbe_clock_set_rate()` → `cal_dfs_set_rate(cal_id, clk)` → `exynos_acpm_set_rate(GET_IDX(id), rate)`
  → IPC `{id, rate_kHz, FREQ_REQ, 0}`. A unidade é **kHz** (a tabela da GPU está em kHz). O driver mainline
  `acpm_dvfs_set_rate()` recebe Hz e divide por 1000, então o formato é o mesmo.
- Tensão: nem `drivers/gpu/arm/exynos` nem `cal_dfs_set_rate` chamam regulador para a G3D
  (`grep regulator_|set_volt` vazio); a margem de tensão é um comando ACPM separado (`MARGIN_REQ`).
  Conclusão (inferência a partir do código): **o ACPM aplica a tensão ASV sozinho**, igual à CPU. `gpu_dvs = 0`, `gpu_dynamic_abb = 0` no DT.
- Energia: `set_clock_using_calapi()` recusa mudar o clock com a G3D desligada ("can't set clock in the
  power-off state"). Workaround só do 9830 (`gpexwa_wakeup_clock_9830.c`): antes de desligar a G3D, baixa
  para **377 MHz**; ao religar, restaura se o anterior era maior.
- Tabela (DT do aparelho, `gpu_dvfs_table`): 832, 800, 702, 572, 455, 377, 260, 156 MHz; `gpu_max_clock = 800000`;
  o arrefecimento Samsung usa 800…156 (7 níveis, igual a `/sys` do Android). O ECT tem 14 níveis até 897 MHz.
  A Samsung também acopla G3D alta a pisos de MIF/CPU (`gpu_dvfs_table`: 800 MHz → MIF 2730000); **isso não foi portado**.

## O que o patch faz (proposta nossa, compila)

1. `drivers/clk/samsung/clk-exynos990-acpm-g3d.c` (novo, `CONFIG_EXYNOS990_ACPM_G3D_CLK`, default y):
   clk filho do nó ACPM, canal DVFS 5, ID 10. Substitui o `fixed-clock` de 800 MHz.
   - Sem IPC no probe. A taxa aparece como 0 até algo defini-la (o Panfrost só a imprime).
   - `set_rate` → `-EPERM` sem `r8s_gpu_dvfs=1` na linha de comando; `-EAGAIN` se o status do `pd_g3d`
     (0x15862204 bit 0, só leitura) indica desligado. Só aceita os 7 níveis 156…800 MHz (arredonda para baixo).
   - debugfs `/sys/kernel/debug/exynos990-g3d/status` (0444): `pd_g3d`, `r8s_gpu_dvfs`, `last_set_khz` e
     `acpm_khz` = `get_rate(10)` — consultado só com a G3D ligada, como a Samsung.
   - debugfs `set_khz` (0200): só existe com `r8s_gpu_dvfs=1`; passa pelo clk core (mesmas verificações).
2. DT (`exynos990.dtsi`): tabela OPP com os 7 níveis, sem `opp-microvolt` (tensão fica com o ACPM),
   `opp-suspend` em 377 MHz (o devfreq baixa para 377 antes do runtime suspend do Panfrost, reproduzindo o
   workaround Samsung), `#cooling-cells` no nó da GPU. `exynos990-r8s.dts`: cooling map da `gpu-thermal`
   (trip passivo 88 °C) para a GPU.
3. Panfrost: devfreq só com `panfrost.r8s_devfreq=1` (parâmetro de módulo). Sem ele, o caminho é o mesmo de
   "sem tabela OPP" do upstream.
4. Config: `CONFIG_DEVFREQ_THERMAL=y` (novo, para o arrefecimento da GPU); `CONFIG_EXYNOS990_ACPM_G3D_CLK=y`.

Com os padrões, nenhuma escrita no ACPM para a G3D acontece no boot.

## Build (resultado: compila, `W=1` sem avisos novos; avisos do dtc já existiam)

```sh
N=gpu-dvfs; docker run --rm -u "$(id -u):$(id -g)" -v /home/joao/Projects/linuxs20fe:/work -w /work/out/agents/$N r8s-kbuild:trixie bash -euc '
B=/work/out/agents/'"$N"'-build; mkdir -p $B
[ -f $B/.config ] || cp /work/out/agents/kernel.config $B/.config
scripts/config --file $B/.config -e DEVFREQ_THERMAL
M="make O=$B ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4"
$M olddefconfig && $M W=1 drivers/clk/samsung/clk-exynos990-acpm-g3d.o drivers/gpu/drm/panfrost/panfrost_devfreq.o drivers/thermal/devfreq_cooling.o exynos/exynos990-r8s.dtb exynos/exynos990-z3s.dtb'
```
Não houve link do kernel inteiro nem `dtbs_check`.

## Plano de teste no aparelho (do mais seguro para o mais arriscado)

Antes de tudo: confirmar que, **sem parâmetros**, o boot, `modprobe panfrost` e o desktop seguem como hoje
(`dmesg | grep -i g3d` deve mostrar `G3D clock via ACPM id 10, DVFS off`; o Panfrost imprime `clock rate = 0`).
Se o clk não fizer probe, o Panfrost fica adiado: sem GPU, mas sem travar.

Medição de temperatura em todas as etapas, em outro terminal:
`while :; do for z in /sys/class/thermal/thermal_zone*; do [ "$(cat $z/type)" = gpu-thermal ] && cat $z/temp; done; sleep 1; done`.
Abortar (parar a carga) acima de 80 °C.

1. **Só ler** (sem parâmetros). Com o Panfrost carregado, segurar a GPU ligada:
   `echo on > /sys/bus/platform/devices/18500000.gpu/power/control`, depois
   `cat /sys/kernel/debug/exynos990-g3d/status` várias vezes, ociosa e com `glmark2-es2-wayland` rodando.
   Esperado: `pd_g3d: on`, `acpm_khz` num dos níveis. Registrar o valor (é a frequência real de hoje,
   o `fixed-clock` de 800 MHz era só um rótulo). Se vier `0` ou fora da tabela, o `get_rate` não serve
   (o driver de cpufreq já diz que não é confiável na CPU) — anotar e seguir sem ele.
2. **Fixar uma frequência** (boot com `r8s_gpu_dvfs=1`, Panfrost **sem** `r8s_devfreq`).
   Com `power/control = on`: `echo 377000 > /sys/kernel/debug/exynos990-g3d/set_khz`, ler `status`, rodar
   glmark2 e comparar a pontuação. Depois 260000 e 156000 (abaixo do atual), e só então 455000 → 572000 → 702000
   → 800000, um passo por vez, cada um com 5 min de carga e temperatura anotada. Antes de devolver
   `power/control` para `auto`, escrever `377000` (o devfreq não está ativo para fazer o workaround de 377 MHz).
3. **devfreq automático**: boot com `r8s_gpu_dvfs=1` e `modprobe panfrost r8s_devfreq=1`.
   Conferir `/sys/class/devfreq/18500000.gpu/{available_frequencies,cur_freq,trans_stat}` e que o
   `gpu-thermal` ganhou um cooling device (`/sys/class/thermal/cooling_device*/type` = `18500000.gpu` ou similar).
   Começar com teto baixo: `echo 455000000 > /sys/class/devfreq/18500000.gpu/max_freq`, subir aos poucos.
   Testar ciclos ocioso↔carga (runtime suspend/resume da G3D) por vários minutos, e um suspend do sistema.

## Riscos

- **Maior risco**: frequências acima da atual sem os pisos de MIF/CPU que a Samsung aplica (800 MHz → MIF 2730 MHz).
  Se o MIF estiver baixo, a GPU pode ficar sem banda ou instável; não sabemos se o ACPM aplica esses pisos sozinho.
  O cpufreq já mostrou travamentos em frequências altas da M5 ligados ao MIF.
- `get_rate` do ACPM pode não ser confiável (já visto na CPU). O driver não depende dele: o devfreq começa em 156 MHz.
- Na etapa 2, se a G3D desligar com a frequência alta, não há o workaround de 377 MHz (por isso `power/control = on`).
- O `set_rate` com a G3D desligada é recusado, mas a leitura do status do PMU e o IPC são novos; se o ACPM
  travar numa requisição, a única saída é desligar o aparelho.
- O patch troca o clock da GPU para todos os boots: se o novo driver não fizer probe, o Panfrost fica sem GPU.

## Perguntas em aberto

- O ACPM do 990 aplica sozinho os pisos MINLOCK (G3D→MIF) ou depende do kernel? O ECT `MINLOCK` analisado
  (`ect-parsed.txt`) não mostra entradas para G3D.
- Vale incluir 832 MHz (está no `gpu_dvfs_table`, mas `gpu_max_clock` é 800)?
- O `pd_g3d` do port não tem `samsung,need-smc` (o kernel Samsung usa `0x18410204` para a G3D); não mexi nisso.


## Resultado da etapa 1, só leitura (19/11/2026, kernel de teste #5 em RAM, observado)

- `/sys/kernel/debug/exynos990-g3d/status` existe; com a GPU segura ligada (`power/control = on`): `pd_g3d: on`, `r8s_gpu_dvfs: 0`, `last_set_khz: 800000`, **`acpm_khz: 0 (not a table level)`**.
- O `get_rate(10)` devolve 0: **não serve para ler a frequência real** (como o plano previa). Os 800 MHz são só o valor registrado pelo kernel.
- `panfrost`: `clock rate = 800000000`, `r8s_devfreq = N`.
- Imagem para a etapa 2: `out/usb3/boot/r8s-ufs-gpu.img` (SHA-256 `f49c38986a5ae3d5…`): mesmo kernel do teste de USB 3, DTB **sem** o USB 3 (`maximum-speed = high-speed`) e `bootargs` com `r8s_gpu_dvfs=1`. Só RAM (`fastboot boot`).
