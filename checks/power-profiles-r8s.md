# Perfis de energia do r8s (Economia / Balanceado / Desempenho)

Testado no aparelho em 19/11/2026, kernel #18, sem flash. Origem: pedido do proprietário (brilho 30/50/80% e CPU e GPU por perfil).

## Como funciona

- `power-profiles-daemon` 0.30 (pacote `extra`) com o driver `fake` (`POWER_PROFILE_DAEMON_FAKE_DRIVER=1`). O kernel não tem `platform_profile` ACPI, e o driver `placeholder` só oferece dois perfis. O menu de bateria do Omarchy usa esse daemon.
- `packaging/power/r8s-power-profile.py` (serviço `r8s-power-profile`, root) escuta o `ActiveProfile` no D-Bus e aplica:

  | Perfil | Brilho | cpu0-3 | cpu4-5 | cpu6-7 | GPU (Mali-G77) |
  |---|---|---|---|---|---|
  | Economia | 30% | 442 MHz (mín.) | 507 MHz (mín.) | 546 MHz (mín.) | 156 MHz (mín., fixa) |
  | Balanceado | 50% | 1157 MHz | 1586 MHz | 1274 MHz | 156 a 455 MHz |
  | Desempenho | 80% | 2002 MHz (máx.) | 2600 MHz (máx.) | 2002 MHz (máx.) | 800 MHz (máx., fixa) |

  Economia é o mínimo de cada grupo, Desempenho o máximo, Balanceado o valor da tabela mais próximo do meio (pedido do proprietário, 19/11/2026). Antes, Balanceado era o pin de `r8s-safe-freq` (1456 / 1690 / 1586 MHz).
- Cada perfil também liga (Economia, Balanceado) ou desliga (Desempenho) a economia de energia do Wi-Fi com `iw ... set power_save`. O Omarchy força `wifi.powersave = 2` (desligada) no NetworkManager; `packaging/power/r8s-wifi-powersave.conf` entra como `zz-r8s-wifi-powersave.conf` com `1` (ignorar) para o serviço decidir.
- Instalação: `packaging/power/install-power.sh` (root).

## Decisões e limites

- **CPU fixa por perfil, não liberada.** Os clusters seguem presos (mínimo igual ao máximo) e cada troca de perfil move um cluster por vez, com 0,5 s entre eles e verificação de erros ACPM no `dmesg`. Liberar o `cpufreq` (modo `dyn`) é o caso em que o DVFS via ACPM deu `-110` e um núcleo travou (`sources/port/device/r8s-safe-freq`). "CPU liberada" no Desempenho quer dizer pin mais alto (sem chegar a 2600/2002 MHz de teto).
- **GPU não é controlada.** Não há `devfreq` para a Mali neste kernel (clock fixo, ver `research/gpu-dvfs.md`). Nenhum perfil muda a frequência da GPU.
- **O freio térmico vence.** Em 70 °C (`r8s-thermal-trip`) o kernel limita as CPUs ao mínimo e ignora o pin. Com o modem ligado o aparelho ficou em 67-68 °C parado, com o grupo cpu0-3 em 442 MHz. O freio soltou quando a temperatura caiu para ~59 °C.

## Resultado (observado)

- Troca entre os três perfis: pins e brilho conferidos (307, 512 e 818 de 1023), sem erro ACPM, sem travamento.
- Corrente da bateria com o modem ligado e tela acesa: Desempenho -479 mA, Balanceado -467 mA, Economia -360 mA (cerca de 100 mA a menos, em grande parte pelo brilho).
- Em repouso, Desempenho e Balanceado quase não diferem. A diferença aparece sob carga, não medida.
- Uma medição isolada mostrou a thread de renderização do shell com 30% de CPU. Não se repetiu depois de recarregar os plugins e não foi atribuída a nenhum widget.

## Auditoria do kernel em execução (19/11/2026, observado)

- **Medido, aplicado:** economia do Wi-Fi ligada: -346 e -360 mA desligada, -287 mA ligada (modem registrado, tela acesa). Cerca de 60 a 70 mA.
- **Limite térmico por perfil, testado e retirado:** com histerese de 5 °C, subir o limite não soltava o freio: o grupo cpu6/7 ficou em 546 MHz (estado 14/14) com a temperatura em 59 °C, e reiniciar o modo da zona não ajudou. Os limites ficam em 70 °C (`r8s-thermal-trip`).
- **Não aplicado, precisa de teste (observado na configuração):**
  - `clk_ignore_unused` na linha de comando: nenhum clock ocioso é desligado. Mantido de propósito pelo projeto (`research/ufs-clocks.md`); remover pode travar o boot. Só em `fastboot boot` (RAM).
  - `cpu-big-sleep` (cpu6/7) desabilitado: usos 0, esses núcleos só fazem WFI (`research/cpuidle-m5.md`). Habilitar travou núcleos; não repetir sem teste em RAM.
  - THP em `always` (5,6 GB de RAM): `madvise` reduziria compactação e memória, sem medição.
  - `HZ=250` com `PREEMPT` completo: `PREEMPT_VOLUNTARY` e `HZ=100` poupam pouco; exigem compilar e testar o kernel.
  - GPU sem `devfreq` (clock fixo): nenhum perfil muda a GPU (`research/gpu-dvfs.md`).
  - O modem continua o maior consumo extra (~300 mA): faltam o sono do link PCIe e do CP.

## CPU nos extremos (19/11/2026)

- **Desempenho no máximo** tem risco documentado: o cluster M5 (cpu6/7) travou duas vezes em 04/09/2026, uma na transição para o teto de 2522 MHz e outra já limitado a 2002 MHz (`sources/port/device/r8s-safe-freq`). O pin fixo evita as transições que o ACPM atrasa (-110), mas o freio térmico em 70 °C as faz de novo. Se travar, reiniciar; voltar para Balanceado.
- **Não validado nos extremos**: no teste o aparelho estava a 68-75 °C (carregando, com modem), com o freio térmico em estado máximo e as três CPUs forçadas ao mínimo, o que mascara qualquer valor de perfil. As escritas e a ausência de erros ACPM estão confirmadas (0 erros); a frequência real só aparece com o aparelho abaixo de ~65 °C.
- Com as CPUs no piso e o modem parado por 4 minutos, a temperatura ficou em 68-69 °C: a CPU não era a fonte principal do calor naquele momento.
- **GPU (atualização de 19/11/2026)**: ver a seção seguinte. O texto abaixo vale para o kernel instalado hoje, sem as opções de boot.
- **GPU (kernel sem as opções)**: sem `devfreq`, fixa em 800 MHz (`panfrost: clock rate = 800000000`). O controle existe como opt-in no patch `0102` (`r8s_gpu_dvfs=1` na linha de comando e `set_khz` no debugfs, tabela 156...800 MHz) e **nunca foi testado no aparelho**.

## GPU por perfil (19/11/2026, testado em RAM)

- O serviço escreve os limites do devfreq do Panfrost (`/sys/class/devfreq/18500000.gpu/{min_freq,max_freq}`): Economia 156..156 MHz, Balanceado 156..455 MHz, Desempenho 800..800 MHz. A ordem é piso mínimo, teto e piso final, para a faixa nunca ficar vazia.
- Medido sob carga (`glmark2` com o Mesa `mesa-g77`, `Mali-G77 MC11 (Panfrost)`): Economia 156 MHz; Balanceado 455 MHz (volta a 377 MHz ocioso, o `opp-suspend` da Samsung); Desempenho 800 MHz. Zero erros ACPM. As pontuações do `glmark2` (1036 a 1325) não distinguem os níveis: o teste é limitado pela CPU a partir de ~260 MHz.
- **Só existe com as opções de boot** `r8s_gpu_dvfs=1` (linha de comando, no `bootargs` do DTB) e `panfrost.r8s_devfreq=1`, que o kernel instalado (#17) não tem. Neste kernel o serviço registra "no devfreq on this kernel, left alone" e segue. Para valer sempre, é preciso gravar uma imagem de boot com essas opções (escrita no telefone: só com ordem do proprietário, com backup).

## Extremos da CPU validados (19/11/2026, kernel de teste em RAM, celular a 61-63 °C e sem freio térmico, observado)

- **Sem carga**: o `scaling_cur_freq` de cada grupo é o valor do perfil: Economia 442 / 507 / 546 MHz, Balanceado 1157 / 1586 / 1274 MHz, Desempenho 2002 / 2600 / 2002 MHz. Sem freio térmico (`cooling` 0/0/0).
- **Desempenho com carga em 8 núcleos** (`taskset` + laço): em 2 s a zona dos núcleos grandes foi a **85 °C** e o freio térmico entrou (`cooling` 4/8/4, CPUs 1586 / 1794 / 1586 MHz). O teste foi parado ali (limite de 74 °C). **0 erros ACPM/RCU, 8 núcleos online, sem travar.** O grupo M5 (cpu6/7) a 2002 MHz, o ponto que travou em setembro, passou pelas transições do freio sem travar neste ensaio curto.
- **Recuperação**: 62-65 °C em 5 s depois de tirar a carga; freio solto (0/0/0); perfil devolvido a Balanceado.
- **Leitura**: o máximo de CPU e GPU (Desempenho) só se sustenta em rajadas curtas; sob carga contínua o freio térmico assume em segundos. O ensaio foi de 2 s; não prova ausência de travamento em uso prolongado.

## Início automático no boot (19/11/2026, observado)

- Falha encontrada: `r8s-power-profile.service` estava em `WantedBy=multi-user.target` com `After=power-profiles-daemon.service`, mas o `power-profiles-daemon` roda depois do `multi-user.target`. O systemd registrou `Found ordering cycle` e **apagou o job do meu serviço no boot** (`Job r8s-power-profile.service/start deleted to break ordering cycle`). Resultado: os perfis (CPU, GPU, brilho, Wi-Fi) só valiam depois de eu reiniciar o serviço à mão.
- Correção: `WantedBy=graphical.target`. Verificado no aparelho (kernel de produção em RAM): o serviço inicia e aplica o perfil ativo (`gpu -> 156..156 MHz` etc.). A confirmação no boot a frio exige um reinício.
