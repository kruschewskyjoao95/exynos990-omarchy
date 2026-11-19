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
