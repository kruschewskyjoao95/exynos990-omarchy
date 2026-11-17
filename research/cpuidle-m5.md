# C2 nos núcleos Mongoose M5 (cpu6/cpu7)

Agente `cpuidle-m5`. Patch `packaging/kernel-patches/0103-cpuidle-m5-arm64-dts-exynos990-add-M5-C2-idle-state-registered-.patch`, branch `feat/cpuidle-m5` (commit `5648f19b660b`, sobre `r8s-port-base`). **Nada foi testado no aparelho.**

## Conclusão

O patch faz sentido desde que o estado venha desligado. Ele declara o C2 do M5 no DT, mas o kernel o registra **desligado** (`CPUIDLE_FLAG_OFF`). Com o patch, cpu6/7 continuam em WFI até alguém escrever `0` em `/sys/devices/system/cpu/cpu{6,7}/cpuidle/state1/disable`. Escrever `1` desliga o estado de novo em execução.

## Por que o autor deixou o M5 sem C2

- **Relatado pelo autor** (comentário em `exynos990.dtsi`, patch 0013): em 2026-09-05, uma sonda em espaço de usuário que desligava e religava a cpu7 travou o SoC sem pânico. Por isso o M5 ficou em WFI "até a sequência de wake ser entendida". O `c2probe` recusa as máscaras das cpu6/7, então o autor nunca testou C2 no M5.
- **Relatado pelo autor** (`device/r8s-safe-freq`): religar cpu6/7 depois de `CPU_OFF` é instável. A primeira tentativa falhou com `failed in unknown state : 0x0` e a segunda deu certo. Isso acontece no hotplug (`CPU_OFF`/`CPU_ON`), que não é o caminho do C2 (`CPU_SUSPEND`).
- **Relatado pelo autor**: os travamentos de núcleo morto que motivaram a cautela vinham do mapa de memória (patch 0024) e atingiam qualquer cluster. O autor também registra que o travamento voltou com o C2 desligado em todas as CPUs ("c2 experiment disproved").

## O que o kernel Samsung faz no idle do M5 (observado no código, LineageOS `97369af7`)

- `cpuidle-exynos64.c`: `cpu_pm_enter()` → `exynos_cpu_pm_enter()` → `arm_cpuidle_suspend()`. Na saída, `exynos_cpu_pm_exit()`.
- `exynos-cpupm.c`: `cal_cpu_disable(cpu)` antes e `cal_cpu_enable(cpu)` depois. CPD (cluster) e SICD só entram se todos os irmãos estiverem ociosos, e acrescentam `psci-index` 0x80/0x100 ao parâmetro. O mainline nunca pede isso: com 0x10000 só o núcleo desliga e o cluster fica ligado.
- `flexpmu_cal_cpu_exynos9830.h` (ramo `#ifndef ACPM_FRAMEWORK`): `core20_off`/`core21_off` têm **a mesma sequência** dos outros núcleos: GRP2_INTR_BID_ENABLE bits 6/7, limpeza de GRP1 bits 6/7 e 14/15, INT_EN 0x1544/0x15c4 bit 3. Na entrada, `CPU_INFORM` (0x878/0x87c) recebe C2. O `exynos990-cpu-wake` do port já cobre cpu6/7 com esses mesmos offsets.
- Só o M5 tem `cluster2_on` (escreve `0xffffffff` em `SYSREG_CPUCL2_BUS_COMPONENT_DRCG_EN`, 0x1D100104). Isso roda só ao religar o cluster (CPD ou hotplug do último núcleo), nunca no C2 de núcleo. O port não faz isso, o que pode ter relação com a instabilidade do hotplug (hipótese).
- Os outros notificadores `cpu_pm` do kernel Samsung são de depuração e perfil (ehld, coresight, halt, cpu-profiler). Não há aviso ao ACPM nem handshake de cluster específico do M5 no C2. O UCC (`cpuidle-ucc`, cstate "6-7") é política de desempenho, não requisito de segurança.
- DT Samsung (`rt.dts`): `lion-cpu-sleep` usa `arm,psci-suspend-param = <0x10000>` (igual a ananke/enyo), com entrada 235, saída 220 e residência mínima de 1000 µs. Os `reg` das CPUs M5 são `0x100/0x101`, enquanto o port usa `6/7`.
- **Medido no aparelho, kernel Samsung** (`cpuidle-cpufreq.txt`): o state1 `lion-cpu-sleep` tem usage 363 na cpu6 e 263 na cpu7. Com o firmware deste aparelho, o M5 entra em C2 e volta.
- MPIDR do M5 (dmesg Samsung): 0x10000 e 0x10100. Fiz a conta à mão: o hash reconstruído pelo patch 0018 com MPIDRs reais fica sem colisão, com 16 slots, cpu6 no 8 e cpu7 no 9. Só vale se cpu6/7 estiverem online no `core_initcall`.

## O que o patch muda (proposta nossa)

1. `exynos990.dtsi`: adiciona o nó `BIG_CPU_SLEEP` (`c2`, `local-timer-stop`, `linux,default-off`, param 0x10000, entrada 235 µs, saída 220 µs, residência mínima 2500 µs) e o referencia em `cpu-idle-states` de cpu6/7. As latências vêm do DT Samsung. A residência de 2500 µs segue o que o port usa no A76 (o vendor usa 1000).
2. `drivers/cpuidle/dt_idle_states.c`: a propriedade `linux,default-off` vira `CPUIDLE_FLAG_OFF`. O núcleo do cpuidle então inicia o estado com `disable=1` (`DISABLED_BY_USER`), e o `default_status` em sysfs mostra `disabled`.

Com o estado desligado, cpu6/7 passam a ter um dispositivo cpuidle cujo único estado ativo é o WFI (`psci_enter_idle_state` com índice 0 chama `cpu_do_idle`). É a mesma instrução que o idle padrão já executava (observado no código, não testado).

### Outras formas de deixar desligado por padrão, descartadas
- Uma unit systemd que escreva `1` no boot: entre o `device_initcall` e o espaço de usuário o M5 já entraria em C2.
- `status = "disabled"` no nó: o estado nem é registrado e não dá para ligar em execução.
- `cpuidle.off=1`: desliga o C2 de todos os clusters.

## Build (executado)

```sh
N=cpuidle-m5; docker run --rm -u "$(id -u):$(id -g)" -v /home/joao/Projects/linuxs20fe:/work -w /work/out/agents/$N r8s-kbuild:trixie bash -euc '
B=/work/out/agents/'"$N"'-build; mkdir -p $B
[ -f $B/.config ] || cp /work/out/agents/kernel.config $B/.config
M="make O=$B ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4"
$M olddefconfig && $M W=1 drivers/cpuidle/dt_idle_states.o exynos/exynos990-r8s.dtb'
```

Resultado: `dt_idle_states.o` compila sem warning com W=1, e o dtb compila. Os 3 warnings do dtc já existiam antes (`system-controller@11860000`, `phy@135d0000`, `/soc@0` duplicado). DTB: `out/agents/cpuidle-m5-build/arch/arm64/boot/dts/exynos/exynos990-r8s.dtb`, sha256 `cf4b6855…a9ab6a`. Decompilei o DTB e conferi: cpu@200 e cpu@201 apontam para `cpu-big-sleep` com `linux,default-off` e `local-timer-stop`. Nenhuma opção `CONFIG_` foi alterada; as necessárias já estão ligadas: `ARM_PSCI_CPUIDLE`, `DT_IDLE_STATES`, `CLKSRC_EXYNOS_MCT` e `EXYNOS990_CPU_WAKE`. Não compilei o Image completo.

## Plano de teste no aparelho (do mais seguro para o mais arriscado)

Pré-requisitos: Image e DTB do **mesmo** build com 0103. Boot em RAM se a rota permitir. ramoops e `r8s-pstore-archive` ativos, softdog com tempo maior que `rcu_cpu_stall_timeout`, ssh ou serial. **Nunca** fazer hotplug de cpu6/7 durante o teste (`/etc/r8s/cpucl2` em `on`).

0. **Padrão (sem risco novo):** `cat /sys/devices/system/cpu/cpu{6,7}/cpuidle/state1/{name,default_status,disable,usage}` deve dar `cpu-big-sleep`, `disabled`, `1`, `0`. `usage` precisa continuar em 0 depois de 10 min de uso normal. No dmesg, conferir a reconstrução do hash MPIDR e o probe do `exynos990-cpu-wake`. Conferir também `/sys/devices/system/clockevents/broadcast/current_device` e os estados da A55/A76 sem mudança.
1. **Só cpu7, ocioso:** `echo 0 > /sys/devices/system/cpu/cpu7/cpuidle/state1/disable`. A cada 10 s por 5 min, registrar `usage`, `time` e `above/below` do state1 da cpu7, mais as linhas MCT e IPI de `/proc/interrupts`. Espera-se `usage` subindo e nenhum `rcu: INFO`.
2. **Só cpu7, carga intermitente, 15 min:** `cyclictest -a 7 -t1 -p 80 -i 10000 -l 90000` (mede o wake por timer na própria cpu7; um `Max` na casa de dezenas de ms indica wake perdido). Em paralelo, rodar `stress-ng --cpu 1 --taskset 7 --cpu-load 30 --timeout 15m`.
3. **cpu6 + cpu7, 30 min:** repetir 1 e 2 com as duas ligadas. Aqui os dois núcleos do cluster desligam ao mesmo tempo, o que exercita a lógica de "último núcleo" do firmware.
4. **Uso real, 2 h ou mais:** desktop e jogo com as duas ligadas. Só depois disso, considerar uma unit que escreva `0` no boot. O DTB continua com o padrão desligado.

Parada: qualquer RCU stall, `usage` da cpu7 parado com a cpu online, `cyclictest` com `Max` acima de 50 ms ou ssh travado. Para voltar, `echo 1 > .../state1/disable`. Se o sistema travar, o único caminho é desligar o celular.

## Riscos

- **Núcleo morto ou SoC travado** na entrada ou saída de C2 do M5. Esse caminho do firmware nunca foi exercitado sob Linux mainline, e o travamento da cpu7 em 2026-09-05 continua sem explicação.
- **Wake perdido** vira RCU stall e reboot por `panic_on_rcu_stall`. O roteamento GRP2 é compartilhado, mas já está serializado (0015/0017).
- **DTB novo com kernel antigo:** um kernel sem a mudança em `dt_idle_states.c` ignora `linux,default-off` e **liga o C2 do M5 no boot**. Image e DTB precisam sair juntos.
- `linux,default-off` não é binding upstream: `dtbs_check` vai reclamar.
- O ganho de energia não foi medido.

## Perguntas em aberto

- O que exatamente a sonda de 2026-09-05 fez na cpu7 (hotplug por sysfs? `/dev/mem`?)? O repositório do port não traz o log.
- O firmware espera `0x100/0x101` (os `reg` do DT Samsung) como alvo de `CPU_ON` para o M5? Isso explicaria a instabilidade do hotplug. O resultado do `psciquery` não foi publicado. Não afeta `CPU_SUSPEND`.
- O `arch/arm64` do kernel Samsung não está no checkout parcial. Não confirmei que não haja código específico do Mongoose em `suspend.c`, `sleep.S` ou `cpu_errata.c`.
- Falta decidir entre residência mínima de 1000 µs (vendor) e 2500 µs (atual), depois de medir.
