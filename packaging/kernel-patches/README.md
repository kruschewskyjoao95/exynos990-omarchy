# Patches extras do kernel (r8s)

Aplicados depois dos 24 patches do port (`sources/port/kernel/patches`), sobre `75138397`. O build padrão (`baseline`) inclui só `0100`; `R8S_KERNEL_PATCHSET=series` seleciona a lista experimental `series`, na ordem escrita. Nenhum foi testado no aparelho.

| Patch | Autor | Na series | Opt-in / condição | Relatório |
| --- | --- | --- | --- | --- |
| `0100` memória 6 GB | gemini | sim | — (corrige o mapa de 8 GB do port) | `COORDENACAO.md` item 6 |
| `0101` vibração MAX77705 | claude (subagente) | **não** | Entra no `series` só depois de `devmem 0x106f0000 32` responder no aparelho com o DTB antigo: o patch ativa o bloco PWM no boot e o gate `GATE_PERIC0_TOP1_PWM` não é modelado. Precisa de `CONFIG_INPUT_MAX77693_HAPTIC=m` | `research/haptic.md` |
| `0102` DVFS da GPU | claude (subagente) | sim | Clock fixo como antes; muda frequência só com `r8s_gpu_dvfs=1` + `panfrost.r8s_devfreq=1`. Precisa de `CONFIG_DEVFREQ_THERMAL=y` | `research/gpu-dvfs.md` |
| `0103` C2 nos núcleos M5 | claude (subagente) | sim | Estado registrado desligado; liga por `/sys/devices/system/cpu/cpu7/cpuidle/state1/disable` | `research/cpuidle-m5.md` |
| `0104` bateria / I2C | claude (subagente) | sim | Repete transferências HSI2C que estouram o tempo (como o kernel Samsung, em todos os barramentos) + 4500 mAh e limites de saúde no DTS. Muda comportamento padrão: uma escrita que estourou o tempo pode ser reenviada | `research/fuelgauge.md` |
| `0105` suspensão profunda | claude (subagente) | sim | Nada muda sem `exynos990_cpu_wake.sleep_prep=` (bit 0: fontes de wake, bit 1: dica SLEEP) ou `psci.system_sleep_power_state=0` | `research/suspend.md` |

O DTB vai dentro da imagem de boot junto com o kernel: os dois têm de sair do mesmo build (o `0103` depende disso).

**Ordem de teste no aparelho:** o primeiro teste em RAM usa só os 24 do port + `0100`. Só depois de ele subir, testar com a `series` inteira, para separar falha do port de falha nossa. `0101` só depois do teste do PWM.

**Build:** `bash packaging/build-env/build-m1-kernel.sh kernel` produz a base; `R8S_KERNEL_PATCHSET=series bash packaging/build-env/build-m1-kernel.sh kernel` produz o conjunto experimental e habilita `CONFIG_DEVFREQ_THERMAL`. O antigo modo `dtbs` aborta antes de alterar saídas: os patches agora também mudam código do kernel. Após cada build completo, regenerar os initramfs e o rootfs com os módulos produzidos, depois executar `package`. As duas variantes usam `out/`; preservar uma cópia do conjunto básico antes de construir a experimental. A seleção não modifica imagens já geradas.

**Verificação no computador:** `python3 checks/test-build-recipes.py` exercita a receita com ferramentas de compilação simuladas, conferindo seleção/ordem dos patches e rejeição de entradas inválidas. Isso não substitui uma compilação completa nem o teste no telefone.

**Coerência do empacotamento:** `package` confere os hashes de kernel/DTB/módulos, dos initramfs presentes e exige o DTB stock. O build `slim` registra uma cópia do manifesto do kernel em `out/boot/initramfs-slim.kernel.sha256`; o empacotamento exige igualdade com o manifesto atual. O slim antigo, sem esse arquivo, precisa ser regenerado, mesmo que `kernelrelease` seja igual. Não criar o registro manualmente para contornar a verificação. O mini não contém módulos e recebe apenas a verificação de integridade. O hash comprova quais entradas foram usadas pelo slim; não comprova que o rootfs Arch existente foi regenerado, nem autoriza builds concorrentes sobre `out/`.
