# Resumo do projeto e encerramento dos testes no aparelho

Data: 17/11/2026. Alvo: Samsung Galaxy S20 FE SM-G780F, Exynos 990, r8s, 6 GB de RAM e armazenamento UFS de aproximadamente 128 GB.

## Objetivo e rota escolhida

Substituir o sistema Android por Linux nativo, usando a cadeia de boot/kernel/DTB/Mesa do port r8s, rootfs Arch Linux ARM e ambiente real do Omarchy adaptado. Não era instalar uma ISO x86 de computador nem apenas copiar um tema. LineageOS serviu como sistema anterior e referência de drivers; Halium/libhybris ficou como alternativa, não como etapa obrigatória.

Por decisão do proprietário, não se instalaria um Debian completo. Debian slim foi usado apenas como diagnóstico em RAM; o rootfs persistente planejado era Arch ARM, seguido do instalador Omarchy.

## Trabalho no computador

- Fontes principais identificadas e fixadas por commit; receitas de kernel, lk3rd, uniLoader, initramfs, rootfs Arch e Mesa preparadas.
- Corrigido mapa de RAM do port, que assumia 8 GB, para os 6 GB observados neste aparelho (patch 0100).
- Construídos kernel AArch64, DTB r8s, módulos, mini/slim em RAM e imagens de boot. Produzido rootfs Arch ARM de 700 MiB, sem gravação no telefone.
- Criado/adaptado instalador Omarchy e glue r8s. Ajustes de pacotes, identidade Arch após branding Omarchy, transação pacman, dependências Mesa/spirv-tools e comando correto de lock.
- Instalador completo executado em userspace ARM64 via Docker/QEMU, com 470 pacotes; unidades systemd verificadas e bibliotecas gráficas inspecionadas. Isso não comprovou GPU ou desktop no telefone.
- Travas de modelo, root, arquivos não vazios, hashes antes/depois da escrita, tamanho máximo da imagem RAM e procedência kernel/DTB/módulos/initramfs reforçadas. Corrigido roteiro Heimdall que usava TAR em vez da imagem crua; esse transporte não foi usado na instalação física.
- Ensaios em uma etapa: 17 testes de build, 10 de instalador, 18 de flash simulado e 56 verificações de artefatos aprovados. Após 0107: 23 testes de build/conjunto/quirk aprovados, além de build completo do kernel/módulos/DTBs. São verificações de etapas distintas, não certificação integral do sistema.
- Patches experimentais de GPU DVFS, idle CPU, I2C e suspensão foram desenvolvidos/compilados em separado. Os ensaios físicos descritos usaram baseline + 0100 e, depois, + 0107, sem misturar a série experimental.

O Hyprland ARM64 não teve sessão gráfica aprovada: tentativa headless/emulada sem DRM abortou ao criar backend; outra verificação não encerrou. Não se registrou isso como sucesso gráfico.

## Backups e preparação do telefone

O proprietário informou que havia formatado o aparelho e não tinha dados pessoais nele. Foram verificados backups de boot, Recovery, DTBO e partições de identidade/calibração, entre outros arquivos. Cópia externa no HD USB: 23 arquivos, 400.893.292 bytes, hashes iguais à origem e manifesto original 10/10 aprovado. Não foi feito dump completo de todos os 128 GB de userdata.

O Android inicialmente fornecia ADB uid 2000. Após entrar no Lineage Recovery e ativar ADB, houve root uid 0, com SM-G780F/r8s conferido. Boot original tinha 59 MiB; Recovery e DTBO tiveram seus hashes registrados.

## O que foi escrito e o que rodou no aparelho

Foi instalado lk3rd no boot pelo Recovery, com upload verificado e readback aprovado. Essa foi uma mudança persistente. No primeiro boot, o próprio lk3rd alterou a GPT para separar a antiga região boot em lk3rd de 2 MiB (`sda13`) e slot boot de 57 MiB (`sda33`). Userdata permaneceu `sda32`; Recovery continuou preservado.

Depois foram executados boots temporários por fastboot:

1. **Mini em RAM:** Linux AArch64 iniciou, USB/console respondeu e retorno ao lk3rd foi confirmado.
2. **Slim em RAM:** Debian 13 diagnóstico iniciou com kernel `6.12.0-rc5-next-20241104-r8s`, systemd running e zero unidades falhas. Nenhuma UFS montada pelos ensaios.
3. **Slim com patch 0107:** novo kernel/DTB/módulos empacotados, tamanho de 63.145.984 bytes conferido e payloads inspecionados. Boot e diagnóstico físicos concluíram.

Panfrost identificou Mali-G77 e criou dispositivos DRM; driver Zinitix registrou touchscreen/input. Isso comprova probe/enumeração, não renderização acelerada, toque calibrado ou desktop utilizável. Não se iniciou Omarchy/Hyprland gráfico no aparelho. Não se gravou rootfs Arch, Debian completo ou kernel Linux permanente no slot boot.

## Problemas encontrados e tratamento

### UFS e clocks

Quatro erros DME pertenciam ao lote de override/máscara de sincronismo UFS (0x9540 e 0x321), apesar de o link negociar G3, duas lanes e permanecer ativo. Leituras comparadas aos backups passaram.

O timeout `18c00000` era do CMU de áudio, dependente de `pd_aud` que o port desabilita para evitar problema TZPC/suspensão. O CLKOUT falhava porque seu driver não reconhecia o compatible da PMU do r8s. `clk_ignore_unused` era uma opção intencional, não um desses defeitos.

Patch 0107: quirk exclusivo Exynos990 evita o lote UFS rejeitado, CMU_AUD fica desabilitado junto do provider e a PMU deixa de criar o filho CLKOUT sem suporte. Sem remover logs do core UFS ou habilitar domínio de áudio inseguro. Testado no telefone: avisos antigos ausentes, G3/2 lanes ativo, três leituras completas de recovery e três de DTBO iguais aos backups, 13 contadores UFS zerados, dmesg sem mudanças durante o ensaio. Não equivale a validar escrita persistente ou todos os modos de energia.

### Saúde do armazenamento

Os sysfs reportaram pre-EOL 0x01 e estimativas A/B 0x0B. Depois foi encontrada confirmação independente no log Samsung/Lineage Recovery preservado: `LT: 0xbb`. A fórmula foi conferida no código da mesma revisão do kernel; corresponde a A=B=0x0B e antecede os patches/testes nativos.

Esse é o indicador de vida estimada do armazenamento interno UFS, não da bateria/RAM. Ele indica vida estimada excedida; não permite prever data de falha ou declarar todas as regiões defeituosas. Pre-EOL e estimativas de vida são métricas diferentes. Formatação/patch não reverte ciclos físicos consumidos. O projeto não causou esse indicador, que já aparecia no kernel Samsung anterior. A condição física não foi medida em assistência.

### Outros limites

Bluetooth apresentou timeouts HCI -110. Wi-Fi, toque real, renderização, carga/temperaturas, suspensão e autonomia não tiveram aceite físico completo. Também permaneceram avisos de reguladores, CPU/MPIDR e componentes ausentes. No reboot do slim houve mensagem de conexão ao system scope bus inexistente; retorno ao lk3rd ocorreu, mas a causa da mensagem não foi resolvida.

## Retorno ao LineageOS

Por pedido explícito do proprietário, o aparelho voltou ao LineageOS. Antes da escrita foram salvos o estado atual do boot e das GPTs, copiados/verificados no HD externo. A restauração foi preparada num disco esparso local, com sfdisk e conferência independente de CRC, preservando todas as entradas fora de boot/lk3rd.

O backup original de 59 MiB foi restaurado na sua região completa, e as GPTs foram reunificadas: boot voltou a sda13, entrada 33 removida. Não se tentou encaixar 59 MiB no slot menor. Readbacks de boot/GPT aprovaram; Recovery e DTBO mantiveram hashes originais. Não houve formatação de userdata nem reinstalação completa da ROM.

Boot normal confirmado via ADB:

- Android 17 / `24.0-20261116-NIGHTLY-r8s`.
- `sys.boot_completed=1`, SurfaceFlinger running.
- Kernel Samsung `4.19.325-cip126-st10-g97369af7bbd6`.
- Boot apontando para sda13; lk3rd removido; ADB normal uid 2000.

Bootloader continua desbloqueado (`orange`); não foi feito relock. Não foram ensaiados todos os aplicativos, chamadas ou um segundo reboot após a restauração. O desgaste informado pela UFS não foi reparado ao voltar ao Android.

## Até onde chegamos e o que faltou

**Conseguimos Linux nativo em RAM, com console e leituras UFS verificadas, além do userspace Omarchy instalado em ambiente ARM64 no computador. Não conseguimos entregar Arch/Omarchy instalado, com desktop funcional, no telefone.**

Para isso faltava escolher armazenamento adequado diante do indicador de desgaste, instalar/testar o Arch mínimo persistentemente, repetir boots e recuperação, validar rede/toque/GPU reais, iniciar Hyprland/Omarchy na tela e provar os fluxos essenciais. Depois viriam carga térmica/energia, suspensão e recursos móveis. Áudio interno, chamadas, câmeras e autonomia cotidiana eram etapas adicionais, não automaticamente fornecidas por instalar o desktop.

O alerta de desgaste foi motivo para reconsiderar a instalação persistente; o proprietário escolheu voltar ao LineageOS. Isso não demonstra que Omarchy seja impossível neste modelo, nem que resolver apenas o armazenamento garantiria o desktop: ainda existiam desafios de integração e validação de hardware.

**Estado final:** LineageOS novamente iniciado, fontes/builds/testes preservados no computador e backups externos mantidos. Sem Arch/Omarchy instalado no telefone.

## Evidências principais

- [Validação ARM64 no computador](../manifests/offline-validation.md).
- [Backups externos](m0-external-backup.md).
- [Primeiros boots físicos](m2-device-test.md).
- [Correções UFS/clocks](../research/ufs-clocks-fixes.md) e [ensaio físico 0107](ufs-clocks-ram.md).
- [Confirmação do indicador de saúde UFS](../research/ufs-health.md).
- [Restauração e boot do LineageOS](return-lineage.md).
