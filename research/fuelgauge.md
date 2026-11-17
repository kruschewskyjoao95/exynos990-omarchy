# Medidor de bateria (MAX77705 FG) — agente `fuelgauge`, patch 0104

Status: **compila** (`i2c-exynos5.o`, `max17042_battery.o`, `exynos990-r8s.dtb`). **Nada foi testado no aparelho.**
Patch: `packaging/kernel-patches/0104-fuelgauge-hsi2c-timeout-retry-r8s-battery-data.patch` (branch `feat/fuelgauge`, commit `8e9ffd38`). Aplica sobre `r8s-port-base` e também depois de 0100–0103 (verificado com `git apply --check`).

Marcações: **[código]** observado no código; **[autor]** relatado pelo autor do port; **[vendor-log]** dmesg/DT do aparelho em Android; **[proposta]** nossa; **[datasheet]** conhecimento do datasheet MAX17047/50, não conferido para o MAX77705.

## Como o port lê a bateria hoje

- [código] O nó `fuelgauge@36` do `exynos990.dtsi` (`compatible = "maxim,max17050"`, `maxim,rsns-microohm = <5000>`) usa o driver mainline `max17042_battery.c`, sem nenhuma mudança do port. O barramento é `hsi2c_7` (0x105c0000, `samsung,exynosautov9-hsi2c`, pinos gpp1-6/7, clock fixo de 200 MHz, SPI 404), compartilhado com `typec@66` (+ cliente dummy 0x25) e `charger@69`.
- [código] O driver não escreve o modelo: com DT ele nunca tem `config_data`, então mesmo com POR ele só marca `init_complete`. A única escrita no probe é `SALRT_Th = 0xff00` (alerta de SOC desligado, porque não tem IRQ). O aprendizado do chip (FullCapRep, FullCapNom, RCOMP0, TempCo, Cycles) fica preservado.
- [código] O shunt de 5 mΩ está certo: o driver Samsung usa `fg_resistor = 2` ([vendor-log] `fg_resistor : 2`) e converte a corrente com `15625 * 2 / 100000` mA/LSB = 0,3125 mA = 1,5625 µV / 5 mΩ.
- [código] `hsi2c_7` não tem `clock-frequency` e roda a 100 kHz (div 124). O Samsung roda a 400 kHz ([vendor-log] `105c0000.hsi2c ... OP_CLK = 400000 DIV = 33`). Uma frequência menor só aumenta a margem, então não explica os timeouts.

## Causa provável dos timeouts

Não existe log do port com os timeouts. O que está abaixo vem do código; a confirmação depende do log novo que o patch gera.

1. **Um timeout vira erro na hora (causa de o erro chegar ao usuário, observada no código).** O `i2c-exynos5.c` mainline define `adap.retries = 3`, mas devolve `-ETIMEDOUT` no timeout de 100 ms. O núcleo I²C (`__i2c_transfer`) só repete em `-EAGAIN`, que esse driver só devolve em perda de arbitragem. Então qualquer atraso isolado faz a leitura do sysfs falhar. O Samsung trata isso de duas formas [código, LineageOS `android_kernel_samsung_universal9830` @ `97369af7`]:
   - `drivers/i2c/busses/i2c-exynos5.c` devolve `-EAGAIN` em `rx/tx timeout`, reinicia o controlador e repete a lista inteira de mensagens (`adap.retries = 2`, 100 µs entre tentativas);
   - `drivers/mfd/max77705.c` envolve **todo** acesso ao MAX77705, inclusive o FG em 0x36, com `I2C_RETRY_CNT 3` e um mutex `i2c_lock` comum aos sub-blocos.

   Isso mostra que o próprio fabricante conta com falhas transitórias nesse barramento.
2. **Origem do atraso (hipótese, não comprovada).** O SoC usa C2 nos A55/A76 (patches 0013–0017). O autor mediu que um núcleo em C2 só acordou ~7 s depois, quando chegou uma IRQ qualquer [autor, patch 0014], e escreveu "Hardware wakeup remains unvalidated" [autor, 0016]. O SPI 404 do HSI2C cai num núcleo (normalmente cpu0, um A55 com C2). Se esse núcleo demora a acordar, o hardware termina a transferência e o driver estoura o tempo. O Samsung fixa a afinidade da IRQ no CPU que espera (`irq_force_affinity(..., raw_smp_processor_id())`) e marca o IP como ocupado para o cpuidle (`exynos_update_ip_idle_status`) [código]. O mainline não faz nenhuma das duas coisas.
3. **Descartados ou improváveis:**
   - acesso concorrente entre sub-blocos: no mainline, cada `i2c_transfer` segura o lock do adaptador e cada leitura do regmap (escrita do registrador + leitura com repeated start) é uma única transferência [código];
   - tempestade de IRQ do FG: o `max77705_r8s_typec.c` mascara `INTSRC_FG` [código];
   - chip "dormindo": o m5 responde ao I²C em hibernate [datasheet];
   - USI: mesma configuração do Samsung, sem `clkreq-on` [código].

## O que o patch muda

1. **`i2c-exynos5.c` [proposta, segue o comportamento do vendor]:** em `-ETIMEDOUT`, repete a transferência inteira até `adap->retries` vezes (3, ou seja, 4 tentativas). O controlador já foi resetado em `exynos5_i2c_xfer_msg`. `-ENXIO`/`-EBUSY` continuam sem repetição. Afeta todos os barramentos HSI2C, como no vendor.
2. **Diagnóstico:** o aviso de timeout passou a ter rate limit e mostra `addr`, `INT_STATUS` e `TRANS_STATUS` **antes** do reset, o que separa "a transferência terminou e a IRQ atrasou" (bit TRANS_DONE pendente, mestre ocioso) de "barramento travado" (mestre ocupado). Depois de cada repetição o driver registra `addr 0xNN: recovered|failed after N timeout(s)`.
3. **DT r8s:**
   - `&z3s_battery { charge-full-design-microamp-hours = <4500000>; }`. O nó herdado era do S20 Ultra (5000 mAh). O carregador só usa `voltage-max-design` (4,38 V), e esse valor confere com o r8s (`battery,chg_float_voltage = <0x111c>` = 4380 mV no `rt.dts`), então **o carregamento não muda**.
   - `fuelgauge@36`: `maxim,dead-volt = <3200>` (SW V-empty do vendor) e `maxim,over-volt = <4380>`. Esses dois só alteram o que `health` informa.
   - Temperatura ficou de fora de propósito (ver abaixo).

O driver `max17042` não aceita `monitored-battery`, tabelas, nem os parâmetros `fuelgauge,*` do Samsung (`cv_data`, `qrtable`, `v_empty`...). Para usá-los seria preciso gravá-los no chip, e isso fica fora deste patch.

## Achados que não viraram código

- **A temperatura do FG fica velha.** [vendor-log] `CONFIG(0x0314)` e `battery,thermal_source = <2>` (= ADC no enum `sec_battery_thermal_source`). O `sec_battery` escreve a temperatura do NTC no `TEMPERATURE_REG` pelo `set_property(TEMP)` [código]. O bit 8 (Tex) aceso indica temperatura fornecida pelo host [datasheet]. Nada no port escreve esse registrador, então `temp` no sysfs mostra o último valor gravado pelo Android ou pelo bootloader. A correção precisa de um termistor lido pelo AP, que ainda não existe no mainline; até lá, não use `temp` dessa bateria em política térmica.
- **`charge_full` ≈ 2,93 Ah.** No recovery o Samsung leu `charge_full=2927000` e `charge_full_design=4500000` [vendor-log, roadmap/03]. Pode ser desgaste real: o FullCapRep aprendido corresponde a 65 % do projeto. O mainline vai mostrar `charge_full` = FullCAP (0x10, o mesmo registrador que o Samsung lê) e `charge_full_design` = registrador DesignCap. Esse registrador deve valer ~4079 mAh, que é o `fuelgauge,capacity = <0xfef>` do Samsung, e não 4500 mAh. Isso ainda precisa ser confirmado no aparelho.

## Calibração (`battery_data.dat`) e como usá-la sem publicar

- [código/vendor-log] O `init.exynos990.rc` copia `/system/vendor/firmware/battery_data.dat` para `/efs/Battery/` e escreve o caminho em `batt_update_data`. No dmesg do recovery as duas operações **falharam**: o arquivo de origem não existe e a escrita deu `Permission denied`. O `battery_v2`, que é o driver em uso, **não tem** `batt_update_data`. Só o `drivers/battery/sec_battery_data.c` antigo (`CONFIG_UPDATE_BATTERY_DATA`) lê esse formato.
- **Formato:** é um *patch de propriedades DT*, não uma tabela do gauge. Começa com um registro `{type=INFO, flag, node_name[32], property[68], length}` seguido de `{version, hw_rev, prop_count, value_length}`. Depois vêm `prop_count` registros `{type VALUE|STRING, flag ADD|EDIT|REMOVE, nó, propriedade, length}`, cada um com o valor bruto, e um registro final `type=NONE`. Esses registros editam nós como `battery`/`max77705-fuelgauge` antes do parse.
- **No backup `stock-efs.img` não existe `/Battery`.** A raiz foi listada com `debugfs`, só leitura, a partir de uma cópia no scratchpad que já foi apagada. Não há calibração específica do aparelho para aplicar.
- A calibração que vale de fato está **dentro do chip**: os registradores aprendidos se mantêm enquanto a bateria estiver ligada. Para preservá-la, basta não fazer o driver escrever o modelo, e o patch não escreve. Se o proprietário quiser uma cópia: com o driver carregado, rodar `i2cdump -f -y <bus> 0x36 w` (só leitura) e salvar em arquivo **fora do git** (por exemplo `backups/`, que é ignorado). Restaurar exige escrever no chip, o que seria um passo separado e arriscado; não está proposto aqui.

## Comando de build

```sh
N=fuelgauge; docker run --rm -u "$(id -u):$(id -g)" -v /home/joao/Projects/linuxs20fe:/work -w /work/out/agents/$N r8s-kbuild:trixie bash -euc '
B=/work/out/agents/'"$N"'-build; mkdir -p $B
[ -f $B/.config ] || cp /work/out/agents/kernel.config $B/.config
M="make O=$B ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4"
$M olddefconfig && $M W=1 drivers/i2c/busses/i2c-exynos5.o drivers/power/supply/max17042_battery.o exynos/exynos990-r8s.dtb'
```
Resultado: sem avisos novos (os avisos `simple_bus_reg`/`unique_unit_address` do dtsi já existiam). O dtb decompilado tem `charge-full-design = 4500000`, `dead-volt = 3200`, `over-volt = 4380` e float 4380000 sem alteração. Nenhum `CONFIG_` novo.

## Plano de teste no aparelho (do mais seguro ao mais arriscado)

Tudo abaixo é leitura, exceto o passo 5.

1. **Base sem o patch:** `dmesg | grep -E '105c0000|max170'` e
   `while :; do date +%s; cat /sys/class/power_supply/max170xx_battery/{capacity,voltage_now,current_now,charge_full,charge_full_design,charge_now,health,status,temp} 2>&1 | tr '\n' ' '; echo; sleep 30; done > fg-base.log`
   durante 2 a 4 h. Conte as linhas com `Connection timed out`/`-110` e os `rx timeout` no dmesg. Use os nomes explícitos, sem curinga.
2. **Com o patch, o mesmo loop:** agora o esperado é ver `recovered after N timeout(s)` em vez de falha de leitura. Anote `addr`, `int_status` e `trans_status`. Se o bit TRANS_DONE estiver pendente e o mestre ocioso, a hipótese é IRQ atrasada; se o mestre estiver ocupado, é barramento ou escravo.
3. **Teste da hipótese do cpuidle**, reversível, sem reboot. Ache a IRQ com `grep 105c0000 /proc/interrupts` e mova para um M5 (ele fica em WFI): `echo 40 > /proc/irq/<n>/smp_affinity`. Como alternativa, desligue o C2: `echo 1 > /sys/devices/system/cpu/cpu*/cpuidle/state1/disable`. Compare a taxa de timeouts em 1 h.
4. **Ciclo de carga e descarga:**
   - Descarga de 100 % até ~15 % com tela ligada, depois carga até `status=Full`, registrando `charge_now`, `current_now` e `voltage_now` a cada 60 s. Verifique que `current_now` muda de sinal ao plugar ou tirar o cabo e que `capacity` acompanha `charge_now/charge_full`.
   - Verifique também que `voltage_now` não passa de ~4,38–4,40 V em CV.
   - Compare `charge_full` com os 2,93 Ah do Samsung.
   - Anote se `temp` fica parado enquanto o aparelho esquenta (confirma o Tex).
5. **(Opcional, leitura com `-f`)** `i2cget -f -y <bus> 0x36 0x1d w` (CONFIG) e `0x18 w` (DesignCap), para confirmar o Tex e o valor de DesignCap. `-f` acessa um endereço que já tem driver; é só leitura, mas faça com o aparelho parado.

## Riscos

- A repetição vale para todos os HSI2C. Uma **escrita** que estourou o tempo depois de já ter saído no fio pode ser enviada de novo. Em escritas de registrador isso não muda nada; em comandos (opcode do Type-C, touch) pode duplicar o comando. O vendor faz o mesmo em todos os barramentos.
- No pior caso, uma transferência bloqueia o chamador por 4 × 100 ms.
- Já existia antes, e o patch não corrige: uma IRQ tardia da tentativa anterior pode chegar durante a nova, porque o reset deveria limpar o INT_ENABLE, mas isso não foi verificado no hardware.
- O DT não muda nada no carregamento: a tensão de flutuação continua 4,38 V, conferida com o DT do r8s.

## Perguntas em aberto

- Qual cliente estoura o tempo (0x36, 0x66/0x25 ou 0x69) e com que estado? O log novo responde.
- O C2 atrasa as IRQs de periféricos? Se sim, a correção certa fica no `exynos990-cpu-wake`, e o retry vira só uma defesa.
- Fonte de temperatura da bateria no mainline: qual canal do ADC liga o NTC (`adc-temp` = canal 4 no `rt.dts`, ADC do S2MPS)?
