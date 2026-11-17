# Saúde UFS: confirmação independente de 0x0B

Investigação em 17/11/2026, sem comandos de escrita, formatação ou reset no telefone. O único comando ao aparelho nesta investigação foi `fastboot getvar product`, que confirmou o estado lk3rd.

## Evidência neste aparelho

O kernel mainline baseline e o build com 0107 reportaram A=B=`0x0B` e pre-EOL=`0x01`; ver [ensaio em RAM](../checks/ufs-clocks-ram.md).

**Encontrada confirmação independente no log Samsung já preservado**, sem precisar reiniciar para Recovery:

```text
[    1.499490] exynos-ufs 13100000.ufs: LT: 0xbb
```

Arquivo: `blobs/r8s-device/recovery-root/dmesg.txt:1798`, SHA-256 `f77bc8393aa8866d1094b9b0ebeae16510223d73df4a6e5bab81ae12ecd2a6dc`. A primeira linha identifica o kernel Samsung `4.19.325-cip126-st10-g97369af7bbd6`; o LEIAME da coleta registra LineageOS Recovery, 17/11/2026, antes dos testes nativos e de 0107.

No [código dessa revisão do LineageOS](https://raw.githubusercontent.com/LineageOS/android_kernel_samsung_universal9830/97369af7bbd66581d3e993fea083f3eed02d3c20/drivers/scsi/ufs/ufshcd.c), `ufs_get_device_desc()` lê o descritor de saúde e imprime `health_buf[3]<<4|health_buf[4]`. Os campos são as estimativas A/B. Dentro de sua faixa válida, A=B=0x0B produz 0xbb. O log antigo concorda com os dois sysfs atuais: o indicador antecede os patches do projeto e aparece em dois drivers diferentes. A mesma fonte condiciona Turbo Write à estimativa abaixo do limiar 7; isso é proteção de uso, não reparo físico.

Fonte baixada somente para inspeção: `out/validation/ufs-health/lineage-ufshcd.c`, SHA-256 `94fee9c02593e9c7ed2871c98b334efdcac2dc9e351e62c1412318c6f584d7e9`. Conferidos a revisão do log, a fórmula e sua saída; nenhum código Samsung foi incorporado ao kernel do projeto nesta investigação.

## Interpretação e limite

`0x0B` significa estimativa de vida excedida, baseada em ciclos de programação/apagamento. Pre-EOL acompanha a reserva de blocos; são indicadores diferentes, portanto pre-EOL normal não contradiz automaticamente o desgaste elevado. [Definição dos campos pela Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ufs/ns-ufs-ufs_device_health_descriptor).

A confirmação é do **indicador informado pelo controlador**, não uma medição física independente de todas as células. Não permite calcular quantos dias restam, prever uma falha imediata ou declarar que todas as regiões estão defeituosas. As leituras comparadas aos backups passaram, mas não medem resistência a novas escritas.

NAND tem limite de ciclos; wear leveling distribui o desgaste e não devolve ciclos já consumidos. Formatar, reinstalar, apagar arquivos ou ocultar o contador não rejuvenescem as células. [Explicação técnica da Kioxia sobre desgaste e wear leveling](https://europe.kioxia.com/content/dam/kioxia/shared/business/memory/mlc-nand/asset/productbrief/KIOXIA_Understanding_Wear_Leveling_Tech_Brief.pdf).

## Como tratar no projeto

1. **Uso persistente confiável:** encaminhar para avaliação técnica do armazenamento/placa. Se o desgaste informado for confirmado em diagnóstico de assistência, a correção física é substituir a memória ou a placa, conforme viabilidade e compatibilidade. Não há patch de Linux comprovado que repare esse desgaste. Não foi pesquisada disponibilidade/custo de peças ou assistência para este aparelho.
2. **Continuar desenvolvimento agora:** builds, testes no host e diagnóstico em RAM continuam possíveis. Manter os backups externos verificados. A confirmação de leitura não é aprovação para instalar o rootfs na UFS envelhecida.
3. **Alternativa de laboratório:** estudar rootfs em microSD ou armazenamento externo para reduzir dependência de escrita UFS. Isso exige validação própria de controlador, alimentação, initramfs e recuperação; a cadeia de boot ainda pode depender de UFS. Não é suporte já comprovado nem reparo do chip.
4. **Se houver futura decisão de usar a UFS mesmo assim:** reduzir gravações evita parte do desgaste adicional, mas não restaura confiabilidade. Antes de implementar mitigação, definir workload e armazenamento: por exemplo, zram em vez de swap na UFS, logs voláteis e evitar builds/benchmarks de escrita no telefone. Nenhuma dessas alterações foi aplicada nesta investigação; não desabilitar journaling ou proteções de integridade apenas para economizar escritas.

Não executar secure erase, teste destrutivo, atualização de firmware UFS ou suposto reset de saúde como tentativa de corrigir este indicador. Não há evidência de firmware corretivo para KLUDG4UHDB-B2D1 revisão 0090 neste projeto. O requisito anterior de confirmar em driver Samsung foi atendido pelo log preservado; a pendência agora é a condição física/estratégia de armazenamento, não repetir indefinidamente a mesma leitura mainline.
