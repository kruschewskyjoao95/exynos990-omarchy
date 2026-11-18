# Retorno ao LineageOS concluído — 17/11/2026

Autorização explícita do proprietário: “então vamos voltar ao lineageos”. Após entrada no Recovery, o proprietário ativou ADB. Alvo conferido como SM-G780F/r8s, Recovery uid 0, setor lógico de 4096 bytes, sda de 249.872.384 setores de 512 bytes. Nenhum rootfs Linux havia sido instalado em userdata.

## Preparação

`stock-boot.img` e `lineage-boot.img` têm 61.865.984 bytes e SHA-256 `5a5bd79383d9c3836e5353da4546111a1c61e1e20d3cf3f9143d98160d4d0f7a`, igual à cópia externa e ao registro anterior ao lk3rd. São backups do LineageOS deste aparelho, não firmware de fábrica Samsung.

Antes de escrever foram capturados:

- Primeiro e último MiB do disco, contendo GPT primária/backup e PMBR.
- Região completa de 59 MiB do boot original, que naquele momento continha lk3rd + slot boot vazio.
- Mapa atual e hashes de Recovery/DTBO.

Snapshots e plano foram copiados ao HD externo, subdiretório `return-lineage-before` junto dos backups anteriores; oito arquivos conferidos por SHA-256. Cópias locais em `out/validation/return-lineage/`, fora do Git.

## Restauração preparada e verificada

O backup antigo de 59 MiB não foi escrito na partição nova de 57 MiB. Foi preparado um disco esparso local com os setores GPT reais, usando `sfdisk` 2.42.4 com setor de 4096 bytes. A entrada 13 recuperou nome, tipo, GUID e atributos do boot original conservados na entrada 33, expandindo para cobrir a região de 59 MiB. Entrada 33 removida. Todas as outras 126 entradas foram comparadas byte a byte e permaneceram iguais.

Validação independente em Python conferiu CRC dos headers/tabelas, igualdade das tabelas primária/backup, extensão exata do boot e preservação de PMBR. `sfdisk --verify`: sem erros. A PMBR foi preservada e não foi escrita no telefone; não foi usado o mecanismo de corromper MBR para forçar reconstrução pelo PIT.

Inputs enviados somente para `/tmp` (tmpfs do Recovery) e conferidos antes de escrever. Script de execução local com guardas de identidade, tamanhos, mapa atual e hashes das regiões anteriores. Dry-run aprovado antes de `--write`.

A primeira tentativa de dry-run com leitura O_DIRECT retornou `Invalid argument` no kernel Samsung, sem atingir qualquer escrita. Foi substituída por leitura normal após `sync` e descarte explícito de caches, como nos scripts de restauração do projeto; novo dry-run aprovou. Não foi interpretada como corrupção de dados.

## Escritas realizadas e verificadas

1. Região original do boot: 15.104 blocos de 4096 bytes a partir do bloco 31.120 de `/dev/block/sda`; readback completo igual ao backup LineageOS.
2. GPT backup: cinco blocos a partir de 31.234.043; readback aprovado.
3. GPT primária: cinco blocos a partir de 1; readback aprovado.

Checksums dos payloads GPT: primária `f5fb164da3cd1aa5b39c12f5438515f4e5722c198c549274d29968f0aec6cacf`; backup `1d010682e5a2550f94a1a027aa03e6a813fcecdb90add05236e165031539faea`.

As GPTs foram novamente lidas no host e comparadas aos payloads; CRCs válidos e PMBR preservada. Recovery permaneceu com hash `7979e57224da6d4466b8ed3fd1e94051787daf87044979ea7866eecb953e14d4`; DTBO com `82b59eba3f952bfbc73d9b866105e878783ef40ca5a89bd93b08bdea01c7bd0c`.

Não foram regravados Recovery, DTBO, EFS, sec_efs, super, userdata ou bootloader Samsung. O próprio Recovery montou sec_efs em `/efs`; não foi executado comando de formatação ou escrita nessa partição. O retorno removeu lk3rd e restaurou o boot/GPT; não houve reinstalação completa da ROM nem relock do bootloader.

## Boot normal confirmado

Após `adb reboot`, o sistema confirmou:

```text
modelo: SM-G780F
dispositivo: r8s
Android: 17
LineageOS: 24.0-20261116-NIGHTLY-r8s
sys.boot_completed: 1
surfaceflinger: running
kernel: 4.19.325-cip126-st10-g97369af7bbd6
verifiedbootstate: orange
boot -> /dev/block/sda13
ADB uid: 2000
```

O nó sda33 não foi encontrado no teste de existência após boot. Leituras dos atributos start/size em sysfs foram negadas ao ADB uid 2000; não foi solicitado root. Os limites completos foram verificados nos bytes GPT antes de reiniciar, e o link do boot voltou a sda13. Boot Android concluído não comprova funcionamento de todos os aplicativos/periféricos; não foi ensaiado uso cotidiano ou segundo reboot nesta etapa.

## Evidência e estado final

- `logs/return-lineage-write.log`: SHA-256 `2546da582f77a82f907db3eae31bec675ad8f49c8a7a031478d6cb7cc5aad58a`.
- `logs/return-lineage-android-confirmed.log`: SHA-256 `bd1e12a7a14a531b2f3d468db41c0523a685c9fc70d4db3c865a0763f1f66cda`.
- Demais logs: `logs/return-lineage-*`; staging/plano em `out/validation/return-lineage/`. Script de restauração é específico do estado anterior e **não deve ser executado novamente**.

**Estado final: LineageOS funcionando até boot completo, lk3rd removido, sem Arch/Omarchy instalado no telefone.** O alerta de vida estimada da UFS é preexistente e não foi reparado pela restauração. Fontes, builds e evidências do projeto permanecem no computador e no HD externo.
