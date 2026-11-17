# Suspensão profunda (deep / `mem`) não acorda: causa provável e plano

Agente `suspend`, patch `0105`. Nada aqui foi **testado no aparelho**.

Marcações: **[código]** observado no código-fonte; **[autor]** relatado pelo autor do port; **[proposta]** nossa hipótese ou ideia; **[aparelho]** leitura já registrada do aparelho (kernel Samsung).

Fontes:
- Port: worktree `out/agents/suspend` (`r8s-port-base`), `sources/port/docs/findings/cpu-idle-and-wake.md`, patch 0005 (psci) e patches 0013/0015/0017 (cpu-wake).
- Samsung: LineageOS `android_kernel_samsung_universal9830` @ `97369af7bbd66581d3e993fea083f3eed02d3c20`. Usei o checkout parcial e, de fora dele, baixei `drivers/firmware/psci.c`, `include/linux/psci.h`, `kernel/cpu_pm.c`, `drivers/pinctrl/samsung/pinctrl-exynos.c` e `drivers/irqchip/irq-gic-v3.c` por raw.githubusercontent no mesmo commit.
- DT real: `rt.dts`. Leituras: `blobs/r8s-device/recovery-root/{power.txt,dmesg.txt}`.

## Como o kernel Samsung entra em SLEEP [código]

1. `exynos-pm.c`, `exynos_pm_syscore_suspend()`, chama `exynos_prepare_sys_powerdown(suspend_mode_idx)`. O DT dá `suspend_mode_idx = 8` = `SYS_SLEEP` (`pmucal_system.h`). Quando o PCIe está ligado, o modo é `pcieon_suspend_mode_idx = 13` = `SYS_SLEEP_HSI2ON`.
2. `exynos-powermode.c`, `exynos_set_wakeupmask()`:
   - escreve o EINT_WAKEUP_MASK do PMU (`0x60C`/`0x61C`);
   - zera `WAKEUP_STAT` (`0x3950`, `0x3954`);
   - escreve as fontes de wake do SoC, `WAKEUP_INT_EN 0x3944 = 0x81a6f` e `WAKEUP2_INT_EN 0x3964 = 0x1c & ~0xc = 0x10`. Os valores vêm da coluna 8 de `exynos-powermode/wakeup-masks` em `rt.dts`.
   - Em 0x81a6f o bit 12 é `EINT`, ou seja, as GPIOs de wake, incluindo a tecla power. Os demais são RTC/TRTC, CMGP EINT0/1, VTS e USB_REWA. Os nomes vêm de `exynos-pm/wakeup_stats` no DT.
3. `cal_pm_enter()` → `pmucal_system_enter()`:
   - `pmucal_powermode_hint()` escreve `CPU_INFORM(cpu0) = CPU_INFORM_SLEEP = 4` (`flexpmu_cal_define_exynos9830.h`);
   - depois executa `enter_sleep[]` (`flexpmu_cal_system_exynos9830.h`): `GRP2_INTR_BID_ENABLE` bit0, limpa GRP1, `CLUSTER0_CPU0_INT_EN` bit3, e zera o bit 24 de `HSI1/HSI2 CMU_CONTROLLER_OPTION` (`0x13000800`, `0x13c00800`).
4. A entrada no firmware é **PSCI SYSTEM_SUSPEND** padrão: `psci_suspend_ops` → `psci_system_suspend()`.
   - `psci_suspend_customized_finisher` e `PSCI_SYSTEM_SLEEP` (aff 3 → `0x03000000`) existem em `psci.c`, mas **nada no checkout os chama**. `suspend_psci_idx = 0x400` é lido do DT e nunca usado.
   - [aparelho] `mem_sleep: s2idle [deep]` e `psci: PSCIv1.1 detected` confirmam que o firmware anuncia SYSTEM_SUSPEND, porque só assim o kernel registra `psci_suspend_ops`.
5. Na volta, `exit_sleep[]` zera `WAKEUP_INT_EN`/`WAKEUP2_INT_EN`, limpa pendências e desarma o CPU0. Fora do sono, portanto, essas fontes ficam em 0. `exynos_show_wakeup_reason()` imprime `WAKEUP_STAT`.

O GIC do vendor não salva o distribuidor na suspensão: só há o notifier de CPU_PM (`irq-gic-v3.c`). Nesse ponto ele não difere do mainline. [código]

## O que o port faz hoje [código]

- Não existe nenhum equivalente de `exynos-pm`, `exynos-powermode` nem `cal-if`/flexpmu. `grep` por `0x3944`, `0x3964`, `0x3950` e `WAKEUP_INT_EN` em `drivers/` não acha nada.
- `pinctrl-exynos` escreve só `EINT_WAKEUP_MASK 0x60C` (32 bits). Esse registrador escolhe quais pinos contam; a fonte "EINT" do SoC continua desligada em `0x3944`. `0x61C` (EINT 32–33, gpa4) não é escrito. A tecla power (gpa2-4 → bit 20) cabe em `0x60C`.
- O `syscore` de `kernel/cpu_pm.c` é registrado em `core_initcall`, e os syscore rodam em ordem reversa. Por isso `cpu_pm_suspend()` roda por último, manda `CPU_PM_ENTER` para o `exynos990-cpu-wake`, e `cpu_wake_arm(0)` escreve **`CPU_INFORM(cpu0) = 1` (C2)** imediatamente antes da chamada ao firmware. O vendor deixa 4 (SLEEP) ali.
- A parte GRP2/INT_EN de `enter_sleep[]` o port já faz, porque `cpu_wake_arm()` repete esses bits. O bit 24 de HSI1/HSI2 não é tocado.
- PSCI: patch 0005 + DT `samsung,system-sleep-power-state = <0x03000000>`, ou seja, CPU_SUSPEND com tipo **standby** (bit 16 = 0) em nível de afinidade 3.
  - [autor] "deep SYS_SLEEP never wakes", "never returns from PSCI SYSTEM_SUSPEND".
  - [proposta] As duas tentativas foram feitas sem as fontes de wake e com a dica C2, então essa conclusão sobre SYSTEM_SUSPEND não se sustenta sozinha.
- `exynos990.dtsi` declara `arm,psci-0.2`, e o vendor usa `arm,psci-1.0`. Isso não tem efeito, porque o mainline decide pela versão que o firmware responde (`psci_probe`, `ver >= 1`). [código]

## Hipóteses, da mais à menos provável

| # | Hipótese | Evidência |
|---|----------|-----------|
| H1 | **As fontes de wake do SoC (`WAKEUP_INT_EN`/`WAKEUP2_INT_EN`) não são armadas.** Com o SoC em SLEEP, o PMU/APM não tem evento que inicie a sequência de volta. A tecla power gera um EINT, mas o bit 12 de `0x3944` não está ligado. Isso explica por que s2idle acorda (CPU em WFI/C2, o GIC está vivo) e deep não. | [código] o vendor escreve `0x81a6f`/`0x10` a cada suspensão e 0 na saída; o port não toca nesses registradores. O valor que o bootloader deixa é desconhecido (o patch o imprime). |
| H2 | **Dica errada ao firmware**: `CPU_INFORM(cpu0) = C2` em vez de SLEEP. O APM/EL3 pode executar uma sequência inconsistente, como desligar o SoC esperando um wake de núcleo que não vem. | [código] ordem dos syscore acima; `pmucal_powermode_hint()` no vendor. |
| H3 | **Chamada PSCI errada**: `0x03000000` (standby, aff 3) não é o que o vendor 9830 usa. O vendor usa SYSTEM_SUSPEND. | [código] nenhum chamador de `PSCI_SYSTEM_SLEEP`; `psci_suspend_ops` padrão; [aparelho] PSCI 1.1 e `[deep]`. A observação do autor de que SYSTEM_SUSPEND não volta está confundida por H1/H2. |
| H4 | **O SoC acorda, mas o kernel morre no resume** (UFS sem reinicialização após perder energia, PCIe/Wi-Fi, DPU, ACPM). Visto de fora, isso é igual a "não acorda". | [autor] o relato não distingue os dois casos. O sono é profundo, os blocos HSI perdem estado e o port só guarda o SMU no resume do UFS (patch 0005). |
| H5 | **A entrada em SLEEP é bloqueada ou trava por um IP ativo**: o link PCIe do QCA6390 está ligado (o vendor troca para `SLEEP_HSI2ON`) ou faltou zerar o bit 24 de `HSI1/HSI2 CMU_CONTROLLER_OPTION`. | [código] `pcieon_suspend_available = 1` no DT; `enter_sleep[]`. O significado exato do bit 24 é desconhecido. |

Menos provável: o `EINT_WAKEUP_MASK2` ausente afetaria só gpa4. Também faltam os contadores ACPM (`acpm_get_apsocdn_count`), que o vendor usa para saber se o SoC realmente desceu e se o MIF desceu. O port não tem como medir isso.

## O que mainline/port não fazem (resumo)

1. Não programam as fontes de wake do SoC e não leem/zeram `WAKEUP_STAT`.
2. Não escrevem `CPU_INFORM = SLEEP` e sobrescrevem com C2.
3. Não executam `enter_sleep[]`/`exit_sleep[]` por completo (bit 24 de HSI1/HSI2, DRCG/MEMCLK na saída, `TOP_OUT`/`AUD_OUT`).
4. Não escolhem o modo conforme o PCIe (`SLEEP_HSI2ON`).
5. Não reportam "early wakeup" nem "MIF blocked" via ACPM.

## Patch 0105 (desligado por padrão)

`packaging/kernel-patches/0105-suspend-exynos990-cpu-wake-optional-PMU-prep-for-deep-suspend.patch`, commit `404d501220a5` na branch `feat/suspend`.

- `exynos990_cpu_wake.sleep_prep` (bitmask, padrão 0, gravável em `/sys/module/exynos990_cpu_wake/parameters/`). Os dois bits só agem no caminho syscore, que é exclusivo do deep; s2idle e cpuidle não passam por ele.
  - **bit 0** (H1): guarda `0x3944`/`0x3964`, zera `WAKEUP_STAT`, escreve `0x81a6f`/`0x10`. No resume restaura os valores antigos e imprime `exynos990-cpu-wake: WAKEUP_STAT … (INT_EN was …)`.
  - **bit 1** (H2): `cpu_wake_arm()` escreve SLEEP (4) em vez de C2 no CPU que suspende.
- `psci.system_sleep_power_state` (H3): o padrão continua sendo o valor do DT (`0x03000000`). Com `0`, o kernel usa SYSTEM_SUSPEND, como o vendor. Funciona na linha de comando e em `/sys/module/psci/parameters/`.
- Não incluído: o bit 24 de HSI1/HSI2 e o modo HSI2ON (H5), porque mexem em CMU fora do PMU e o significado é desconhecido.

Build (container `r8s-kbuild:trixie`, `O=out/agents/suspend-build`, config `out/agents/kernel.config` sem mudanças de `CONFIG_`):

```sh
make O=$B ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 olddefconfig
make O=$B ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 W=1 \
  drivers/soc/samsung/exynos990-cpu-wake.o drivers/firmware/psci/psci.o
```

Resultado: os dois objetos compilam sem avisos com `W=1`. Não linkei o kernel.

## Plano de teste no aparelho (do mais seguro ao mais arriscado)

Todo teste usa kernel em RAM (`fastboot boot`, FLASHING.md §4), nunca gravado. Se não acordar, segure Power+Vol− por ~10 s e o aparelho volta ao que estava gravado. Em todos os testes: `no_console_suspend`, ramoops ativo, `echo 1 > /sys/power/pm_debug_messages`, `echo 1 > /sys/power/pm_print_times`. Após um reset forçado, leia `/sys/fs/pstore/console-ramoops*` para separar "não acordou" (log termina antes da chamada PSCI) de "acordou e morreu" (há linhas de resume, como `WAKEUP_STAT` ou `Enabling non-boot CPUs`).

- **E0 (só kernel, sem firmware; isola H4 da parte do kernel)**:

  ```sh
  echo deep > /sys/power/mem_sleep
  for t in freezer devices platform processors core; do
    echo $t > /sys/power/pm_test
    echo mem > /sys/power/state
  done
  echo none > /sys/power/pm_test
  ```

  O nível `core` passa por syscore, CPU_PM e cpu-wake, mas não chama o PSCI. Se algum nível travar, o problema está no kernel, não no firmware. Repita com `sleep_prep=3`.
- **E1 (H1)**: `exynos990_cpu_wake.sleep_prep=1`, PSCI no padrão. Rode `echo mem > /sys/power/state`, espere 10 s e aperte power. Sucesso = voltar e aparecer `WAKEUP_STAT` com o bit 12 (EINT). Se voltar na hora, também é progresso: a linha mostra qual fonte acordou o SoC.
- **E2 (H1+H2)**: `sleep_prep=3`, PSCI no padrão.
- **E3 (H3)**: `sleep_prep=3` + `psci.system_sleep_power_state=0` (SYSTEM_SUSPEND). Faça também `sleep_prep=0` + `psci…=0`, para saber se SYSTEM_SUSPEND sozinho já resolve.
- **E4 (H5)**: repita a melhor combinação de E1–E3 com o Wi-Fi descarregado (`rmmod` do driver QCA6390) e o controlador PCIe desvinculado (`unbind` em `/sys/bus/platform/drivers/<driver pcie>/`).
- **E5 (H4)**: se o pstore mostrar resume começado e morte depois, desligue um driver por vez antes da suspensão (Wi-Fi, painel/DPU) e compare. UFS é a raiz e não pode ser descarregado; nesse caso o próximo passo é ler o resume de `ufs-exynos` contra o vendor.
- Evidência fraca de que o SoC dormiu: a queda de bateria em 1 h de tentativa deep comparada com 1 h de s2idle.

## Riscos

- Com o bit 0 ligado, a suspensão escreve quatro registradores do PMU (`0x3944`/`0x3964`/`0x3950`/`0x3954`). O vendor escreve exatamente esses a cada suspensão, então existem e aceitam escrita [código], mas isso não foi testado aqui. O port já registrou que uma varredura de leitura em `0x1000–0x104c` do PMU travou o SoC. Os offsets do patch são outros e são endereços pontuais, não varredura.
- O pior caso esperado é o atual, não acordar, e a saída é o reset forçado. Um wake imediato e repetido (RTC TICK está na máscara do vendor) também é possível e é inofensivo.
- Se o SoC acordar e o resume corromper o UFS durante uma escrita, há risco ao rootfs. Faça `sync` antes e prefira testar com o rootfs pouco ativo.
- `psci.system_sleep_power_state` é gravável em runtime. Um valor arbitrário vai direto para o EL3: use só `0` ou `0x03000000`.

## Perguntas em aberto

1. Que valor o bootloader deixa em `0x3944`/`0x3964`? O E1 imprime, e um `busybox devmem` de leitura também responderia, desde que o offset fosse considerado seguro.
2. O EL3 usa `CPU_INFORM` com SYSTEM_SUSPEND, ou só o APM o lê? Sem o binário do EL3/APM, só os testes respondem.
3. O bit 24 de `HSI1/HSI2 CMU_CONTROLLER_OPTION` é necessário? Quem registra `pcie_is_connect` no vendor? Não consegui o arquivo PCIe do vendor: a árvore da API veio truncada.
4. O resume de UFS e PCIe do port sobrevive à perda de energia do HSI? Essa é a pergunta do H4, e só aparece depois que o SoC acordar.
