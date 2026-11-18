# Patch 0107 — teste físico em RAM, 17/11/2026

Pedido do proprietário: preparar e executar o necessário para testar no telefone. Alvo previamente identificado: Samsung SM-G780F / r8s. Escopo: boot temporário, inspeção e leituras; sem comandos de flash ou montagem de UFS.

## Conjunto testado

Patch implementado em `536b4c1`, [descrição das correções](../research/ufs-clocks-fixes.md). Fontes fixadas do baseline + 0100 + 0107; sem a série experimental 0102–0105.

Artefatos em `out/validation/ufs-clocks/ram/out/boot/`:

| Artefato | SHA-256 |
| --- | --- |
| Image | `414e655c5879acb648c46ffed1c5e4184207cbf8870043b2292f4a27f64476c1` |
| exynos990-r8s.dtb | `96bd4311189a0fdc0864272b21d97ca45f077e5638da4d580ed79e302d0f6899` |
| initramfs-slim.cpio.gz | `2a7f501b06d52841b7da955b5af2250342692280135ba2b24526ab67123f0bb7` |
| r8s-ram.img | `f05008b7b5232f5797b4c6b1ddcf43f60ea76485c023d1b8bf64256f63763c89` |

A imagem Android tem **63.145.984 bytes**, abaixo do limite lk3rd de 67.108.864. O slim foi derivado do initramfs conhecido (`53a8ed4b…`), substituindo completamente seus módulos pelos do novo build, repetindo a poda da receita e executando `depmod`. Userspace, firmware, init e fstab do diagnóstico foram preservados. O arquivo fstab foi conferido vazio. A procedência fica em `kernel.sha256`, `initramfs-slim.sha256` e `initramfs-slim.kernel.sha256` no diretório isolado.

O empacotamento reutilizou a função `package_uniloader` da receita, redirecionando somente as saídas para o diretório isolado. A imagem foi desempacotada: kernel Android igual ao uniLoader gerado; blobs Image, DTB e ramdisk iguais às entradas; ramdisk externo descomprime para vazio, sem duplicação do initramfs.

## Execução observada

1. Console antigo confirmou Galaxy S20 FE e nenhuma `/dev/sd*` montada. Solicitado reboot; host confirmou `product: r8s - lk3rd` e exatamente um dispositivo fastboot.
2. Hash da imagem conferido antes de `fastboot boot out/validation/ufs-clocks/ram/out/boot/r8s-ram.img`. Envio e boot `OKAY`.
3. USB serial reapareceu com Debian 13 `r8s-slim`, console root. Kernel executado: `6.12.0-rc5-next-20241104-r8s #2 SMP PREEMPT Tue Nov 17 19:19:51 UTC 2026 aarch64`.
4. Diagnóstico com `set -euo pipefail`, aborto se UFS montada e labels recovery/DTBO conferidos antes de ler.
5. Retorno solicitado pelo console; ao final o host confirmou novamente `product: r8s - lk3rd`.

## Resultados

| Verificação | Observado neste aparelho |
| --- | --- |
| Quatro erros DME 0x9540/0x321 | Ausentes no dmesg completo consultado. |
| CMU_AUD | Nó vivo `disabled`, assim como `pd_aud`; dispositivo de plataforma 18c00000 não criado e timeout antigo ausente. |
| CLKOUT | Filho `exynos-clkout` não criado; erro antigo de compatible/probe ausente. |
| Negociação UFS | `FAST series_B G_3 L_2`; sysfs: FAST_MODE, HS_RATE_B, HS_GEAR3, duas lanes, device/link ACTIVE. |
| Montagens | Rootfs em RAM e pseudo-filesystems; nenhuma partição UFS montada antes ou depois. |
| Leituras diretas | Três leituras completas de recovery e três de DTBO coincidiram com os backups. |
| Erros UFS | Todos os 13 contadores zero antes/depois; saved_err e saved_uic_err zero. |
| dmesg durante as leituras | Snapshots idênticos; sem I/O error, Unknown symbol ou version magic no log examinado. |
| Systemd | `running`; zero unidades falhas. |
| Módulo Panfrost | Arquivo no telefone igual ao do staging: SHA-256 `1b503bb55a2eb452bd985ca525eb94b97e7c5049bbc1ba2962eb7d3168a8ae01`. Isso confere o arquivo, não testa renderização. |
| Retorno ao loader | Fastboot `r8s - lk3rd` confirmado após o teste. |

Leituras executadas com `dd if=… bs=1M iflag=direct status=none | sha256sum`, dentro da subshell com `pipefail`. Cada hash foi comparado automaticamente:

- `/dev/sda14`, recovery: `7979e57224da6d4466b8ed3fd1e94051787daf87044979ea7866eecb953e14d4`, três vezes.
- `/dev/sda11`, DTBO: `82b59eba3f952bfbc73d9b866105e878783ef40ca5a89bd93b08bdea01c7bd0c`, três vezes.

Marcadores de êxito foram conferidos na resposta real do console, excluindo a linha que ecoava o comando. O `clk_ignore_unused` e os avisos de reguladores UFS presumidos ligados continuam no baseline; não eram os três achados corrigidos.

## Limites e saúde

O descritor voltou a mostrar `eol_info=0x01`, `life_time_estimation_a=0x0B` e `life_time_estimation_b=0x0B` no kernel novo. É uma segunda leitura com a mesma família de driver, **não confirmação independente em Recovery/Android**. O possível desgaste continua pendente antes de instalação persistente; o patch não corrige desgaste físico.

**Atualização após o ensaio:** encontrada confirmação independente no log Samsung/LineageOS Recovery preservado, `LT: 0xbb`; a fórmula da mesma revisão do driver corresponde a A=B=0x0B. A confirmação no driver Samsung está atendida; a condição física continua sendo uma limitação para instalação persistente. Evidência e opções em [ufs-health.md](../research/ufs-health.md).

Os consoles de reboot, tanto do slim antigo quanto do novo, emitiram `Failed to connect to system scope bus ... No such file or directory`; apesar disso, houve desligamento da USB e retorno ao lk3rd confirmado pelo host. A origem dessa mensagem ainda não foi diagnosticada. Não declarar shutdown silencioso ou recuperação completa a partir desse retorno.

Nenhuma partição foi gravada ou montada por comandos desta sessão; não houve instalação Arch/Omarchy. Sem ensaio de escrita UFS, power-mode/suspensão, carga longa, renderização ou poweroff físico. V2 foi repetido com 0107; V3/V7/V8 continuam incompletos. Os artefatos anteriores em `out/boot/` não foram substituídos. Estado final observado: **lk3rd fastboot**, nenhum processo de coleta serial mantido aberto.

## Logs locais

Logs estão fora do Git, em `logs/ufs-clocks-ram-*`. Entradas principais:

| Log | SHA-256 |
| --- | --- |
| `ufs-clocks-ram-boot.log` | `dd14bf5321b74520acc7931347e4357f9e5f638fff9378078da5f80d739cf5ff` |
| `ufs-clocks-ram-diagnostic.log` | `0b353eaa8959a9a788272ddc2c18a30ab83c634262bea86667f5f2b6dec44d0a` |
| `ufs-clocks-ram-return-fastboot.log` | `8b2be0d3fe0910d0f0a6a24491c494322bef9463d799dea72779e853b11b9daa` |

Preparação adicional: `ufs-clocks-ram-initramfs.log`, `ufs-clocks-ram-package.log`, `ufs-clocks-ram-unpack.log`, `ufs-clocks-ram-precheck.log`, `ufs-clocks-ram-product.log`, `ufs-clocks-ram-return-console.log`.
