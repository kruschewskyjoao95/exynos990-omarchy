# Perfis de energia do r8s (Economia / Balanceado / Desempenho)

Testado no aparelho em 19/11/2026, kernel #18, sem flash. Origem: pedido do proprietário (brilho 30/50/80% e CPU e GPU por perfil).

## Como funciona

- `power-profiles-daemon` 0.30 (pacote `extra`) com o driver `fake` (`POWER_PROFILE_DAEMON_FAKE_DRIVER=1`). O kernel não tem `platform_profile` ACPI, e o driver `placeholder` só oferece dois perfis. O menu de bateria do Omarchy usa esse daemon.
- `packaging/power/r8s-power-profile.py` (serviço `r8s-power-profile`, root) escuta o `ActiveProfile` no D-Bus e aplica:

  | Perfil | Brilho | cpu0-3 | cpu4-5 | cpu6-7 |
  |---|---|---|---|---|
  | Economia | 30% | 806 MHz | 845 MHz | 858 MHz |
  | Balanceado | 50% | 1456 MHz | 1690 MHz | 1586 MHz |
  | Desempenho | 80% | 1846 MHz | 2210 MHz | 1794 MHz |

  Balanceado é o ponto fixo de `r8s-safe-freq`.
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
