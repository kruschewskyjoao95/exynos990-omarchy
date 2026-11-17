# Vibração (haptic MAX77705) no kernel do port

Agente `haptic`, patch `packaging/kernel-patches/0101-haptic-max77705-input-ff.patch` (branch `feat/haptic`, commit `1e1b244de2b2` sobre `r8s-port-base`). **Nada aqui foi testado no aparelho.**

Marcações: **[código]** observado no código; **[DT]** observado no DT real (`rt.dts`) ou nas leituras do aparelho; **[proposta]** decisão nossa; **[testado]** nada.

## O que o aparelho usa

- **[DT]** Nó `haptic` na raiz do DT Samsung (não é filho do MAX77705): `haptic,pwm_id = <1>`, `haptic,period = <37650 65104 52083 39062 43402 39062 39062>` ns (7 frequências; a [0] é a padrão), `haptic,normal_ratio = 88`, `overdrive_ratio = 95`, `high_temp_ratio = 68` acima de `temperature = 550` (55,0 °C), `max_timeout = 10000`, `regulator_name = "VDD_MOTOR_3P3"`, `type = "LINEAR_0832RC"` (LRA). O `dmesg` do kernel Samsung (`blobs/r8s-device/recovery-root/dmesg.txt:4050-4065`) imprime os mesmos valores.
- **[DT]** O pino é `gpp4-5`, função 2 (TOUT1), pull-down (`vib-pwm`), aplicado pelo nó `max77705@66`. O PWM é `pwm@106F0000` (`samsung,s3c6400-pwm`, saídas 0 a 4), com clocks `GATE_PERIC0_TOP1_PWM` (pclk) e `OSCCLK` (sclk, 26 MHz) em `dt-bindings/clock/exynos9830.h`.
- **[DT]** `VDD_MOTOR_3P3` é o **LDO27M do S2MPS19**, 3,3 V. Em `regulators.txt` aparece `enabled`, `users=1`: o driver Samsung liga o regulador no probe e o mantém ligado.
- **[código]** No `max77705_haptic.c` da Samsung (LineageOS `97369af7`), o MAINCTRL1 (0x02) recebe BIASEN no bit 7. O MCONFIG (0x10) recebe LRA no bit 7, EN no bit 6, PWM externo (bit 5 = 0) e divisor 128 (`0b10` em [1:0]). A intensidade vira duty entre 50% (motor parado) e `period*88/100`. O LDO27M fica no registrador `S2MPS19_PMIC_REG_L27CTRL = 0x60` (`s2mps19-regulator.h` no mesmo commit, baixado de raw.githubusercontent).
- **[código]** O layout é idêntico ao do MAX77843 no mainline `max77693-haptic.c` (`MAX77843_SYS_REG_MAINCTRL1 = 0x02`, `MAX77843_HAP_REG_MCONFIG = 0x10`, `MODE` no bit 7, `MEN` no bit 6, `PWM_DIVISOR_128 = 2`). Por isso **estendi o driver mainline** em vez de escrever um novo.

## O que o patch faz

1. **`max77693-haptic.c`** [proposta]: adiciona o tipo `TYPE_MAX77705` (também no enum de `max77693-common.h`) e o compatible `maxim,max77705-haptic`. Ele reusa os caminhos do MAX77843 para o bias e o MCONFIG. Diferenças em relação ao MAX77843:
   - o regmap vem do dispositivo pai (`dev_get_regmap(parent)`), porque o port não tem o MFD core do MAX77705;
   - o duty fica limitado aos 88% da Samsung; o mainline iria a cerca de 100%;
   - o BIASEN é ligado, mas nunca desligado, como faz o vendor, porque outros blocos do PMIC podem depender dele.
2. **`max77705_r8s_typec.c`** [proposta]: esse driver já é dono do cliente I²C 0x66 (topo do PMIC). No fim do probe, ele registra um regmap I²C e chama `devm_of_platform_populate()` para os nós filhos. Uma falha só gera `dev_warn`: o probe do USB-C, que é o canal de recuperação, nunca falha por causa disso. `Kconfig`: `select REGMAP_I2C`.
3. **`s2mps19-acpm-regulator.c`**: adiciona `LDO27M` (reg 0x60, 3,3 V fixos), seguindo o padrão do `BUCK4M`.
4. **DT**:
   - `exynos990.dtsi`: novo nó `pwm: pwm@106f0000`, `samsung,s3c6400-pwm` como no DT do vendor, clock `timers = <&oscclk>`, `disabled`;
   - `exynos990-r8s.dts`: `&pwm` com `samsung,pwm-outputs = <1>` e `okay`;
   - pinos `vib_pwm` (gpp4-5) em `&pinctrl_peric0`;
   - `vdd_motor: ldo27m` em `&acpm_pmic_regulators`;
   - nó `haptic` filho de `typec@66`, com `pwms = <&pwm 1 37650 0>`, `haptic-supply = <&vdd_motor>` e o pinctrl.
5. **Kconfig**: `INPUT_MAX77693_HAPTIC` passa a depender também de `TYPEC_MAX77705_R8S`.

**Opção a ligar no `r8s.config`: `CONFIG_INPUT_MAX77693_HAPTIC=m`.** `INPUT_FF_MEMLESS`, `INPUT_EVDEV`, `PWM_SAMSUNG`, `REGULATOR_S2MPS19_ACPM` e `TYPEC_MAX77705_R8S` já estão no `kernel.config`.

Ficou de fora [proposta]: as 6 frequências alternativas, o overdrive de 95%, a redução para 68% acima de 55 °C (não há ligação com a bateria) e as sysfs da Samsung (`intensity`, `multi_freq`, padrões HAPTIC_ENGINE). O FF_RUMBLE só tem amplitude.

## Build

```sh
N=haptic; docker run --rm -u "$(id -u):$(id -g)" -v /home/joao/Projects/linuxs20fe:/work -w /work/out/agents/$N r8s-kbuild:trixie bash -euc '
B=/work/out/agents/'"$N"'-build; mkdir -p $B
[ -f $B/.config ] || cp /work/out/agents/kernel.config $B/.config
scripts/config --file $B/.config -m INPUT_MAX77693_HAPTIC
M="make O=$B ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4"
$M olddefconfig && $M W=1 drivers/input/misc/max77693-haptic.o drivers/usb/typec/max77705_r8s_typec.o \
  drivers/regulator/s2mps19-acpm-regulator.o drivers/pwm/pwm-samsung.o \
  exynos/exynos990-r8s.dtb exynos/exynos990-z3s.dtb exynos/exynos990-c1s.dtb'
```

Resultado: os 4 objetos compilam com `W=1` sem avisos. Os 3 DTBs compilam; os avisos de DT que aparecem (`simple_bus_reg` e `unique_unit_address`) já existiam e não vêm deste patch. O DTB decompilado contém `haptic` com `pwms = <&pwm 1 0x9312 0>`, `pwm@106f0000` `okay` com `samsung,pwm-outputs = <1>`, `ldo27m` e `vib-pwm-pins`.

## Plano de teste no aparelho (do mais seguro ao mais arriscado)

0. **Bloco PWM legível sem gate de clock.** Antes de usar o DTB novo, dê boot com o kernel e o DTB atuais e rode `devmem 0x106f0000 32` (TCFG0; o reset esperado é 0x101 ou o valor que o bootloader deixou). Se essa leitura travar o aparelho, o `pwm-samsung` também travaria no boot com o DTB novo. Nesse caso, mantenha `&pwm` como `disabled` e modele o gate `GATE_PERIC0_TOP1_PWM`.
1. **Boot com o DTB novo e conferência dos probes:**
   - `dmesg | grep -iE 'pwm|max77705|haptic|LDO27M'`;
   - `ls /sys/class/pwm/` deve listar o pwmchip de 106f0000.pwm;
   - o USB-C deve continuar com o log `MAX77705 USB-C hw .. fw ..` e sem `PMIC child devices (haptic) not created`;
   - `modprobe max77693-haptic` (se a carga automática não acontecer);
   - `cat /proc/bus/input/devices` deve mostrar `max77693-haptic` com `EV=200001`, `FF=...`.
   Nenhuma escrita de hardware acontece até alguém abrir o `/dev/input/eventN`.
2. **Abrir sem vibrar.** Rode `fftest /dev/input/eventN` e saia antes de escolher um efeito. Ao abrir, o driver liga o LDO27M e o BIASEN. No `dmesg`, procure `enable LDO27M: reg 0x60 update ret=0 readback=0x..`. O esperado é **0xFC** (enable 0b11 + código 0x3C = 1,8 V + 60×25 mV = 3,3 V, se o LDO27 for do tipo 1,8 V/25 mV). Os bits [5:0] não são escritos pelo driver. O pior caso do campo é 3,375 V, então ligar não sobe acima do nominal.
3. **Vibração fraca e curta.** No `fftest`, use o efeito "Weak rumble" (rumble com `weak_magnitude`), que dura cerca de 1 s. Em seguida, use o "Strong rumble". Se o motor não vibrar, faça os diagnósticos abaixo; se zumbir de forma estranha, pare.
   - Leia os registradores do PMIC: `cat /sys/kernel/debug/regmap/*-0066/registers | grep -E '^(02|10):'`. Durante o efeito, o esperado é `02` com bit 7 = 1 e `10` = `c2`.
   - Confira o PWM: `cat /sys/kernel/debug/pwm`. O esperado é o canal 1 com período 37650 e duty até cerca de 33132.
4. **Suspend/resume** com o dispositivo aberto e depois fechado: o motor não pode ficar ligado.
5. **feedbackd**: precisa de uma regra udev que marque o evdev como vibra (`ENV{FEEDBACKD_TYPE}="vibra"` ou equivalente). Isso fica fora deste patch.

## Riscos

- **Maior risco: o gate PCLK do PWM não é modelado.** Se o bootloader deixou `GATE_PERIC0_TOP1_PWM` desligado e o bloco não estiver em gate automático, o primeiro acesso do `pwm-samsung` no boot pode gerar um SError ou travar o barramento antes do console. O passo 0 verifica isso antes. O kernel e o DTB anteriores continuam valendo como volta, pela regravação do boot. Não há risco elétrico.
- **Tensão do LDO27M** [proposta]: o driver só liga e desliga os bits [7:6] e não programa a tensão. O endereço 0x60 é confirmado pelo header Samsung. Pelo campo de 6 bits, a faixa vai até cerca de 3,375 V. O regulador só é ligado quando o evdev é aberto e é desligado no close. Se o bootloader o deixou ligado e ninguém o usar, o `regulator_late_cleanup` o desliga cerca de 30 s após o boot (só alimenta o motor).
- **Escrita no MCONFIG**: o mainline grava o registrador inteiro (`0xC2`/`0x82`), enquanto a Samsung faz read-modify-write. Os bits [4:2] ficam em 0; se o reset deles não for 0, há diferença. `haptic,reg2 = 0x82` (MCONFIG2) existe no DT, mas o driver Samsung não o usa.
- **Acoplamento ao driver Type-C**: o motor só aparece se o probe do `max77705_r8s_typec` (módulo) passar. Um `rmmod` desse módulo remove o haptic antes do regmap.
- **Duty**: com o limite de 88%, a força máxima fica igual à normal da Samsung; ficou sem overdrive e sem redução térmica.

## Perguntas em aberto

- O gate do PWM está ligado ou em HWACG depois do S-boot? O passo 0 responde. Como o S-boot vibra ao ligar, há indício de que o PWM fica com clock, mas isso não foi verificado.
- O LDO27 é mesmo do tipo 1,8 V + 25 mV? O driver `s2mps19-regulator.c` do commit `97369af7` deu 404 no raw; o readback do passo 2 responde.
- Vale expor as outras frequências da tabela (120 a 207 Hz), por exemplo com um parâmetro de módulo ou com o período do `pwms`, para afinar a ressonância deste motor?
