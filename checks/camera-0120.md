# Captura da traseira principal do r8s

## Referência no aparelho com 0119

Via SSH USB, o DT identifica `samsung,r8s` e o Arch roda `6.12.0-rc5-next-20241104-r8s`. O journal registra sensor `0x20cd`, revisão `0xa301` e receptor CSIS `0x05030001`. Um segundo ensaio com `timeout 8 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=/tmp/0119-check.raw` gravou zero bytes. No encerramento, INT0, INT1, DMA_INT e DMA_ERR estavam zerados e PHY_STATUS valia `0xf1`. Essa leitura isolada ocorre depois de parar o sensor.

O slot de kernel do lk3rd corresponde a `sda33` (57 MiB). A cópia de retorno do boot 0119 em `out/validation/camera-0119/r8s-ufs.img` tem SHA-256 `475b63ed85986478f1dde6b348d2e9b85cd181f6c4b0c37dca95c3fcbfd7dd0f`. O manifesto dos backups locais de partições passou em dez de dez entradas.

## Implementação e verificações no host

O patch `68225ab` usa a árvore LineageOS universal9830 `97369af7bbd66581d3e993fea083f3eed02d3c20`. O defconfig e o identificador físico correspondem à API CSIS v5.3. Para 2016×1512 a 30 fps, o módulo Samsung define três trios, 2964 Msps, LRTE e VC0 RAW10. O ramo C-PHY do DCPHY 5.3 e a tabela de settle de 7 nm fornecem a programação analógica e o settle 7.

No DTS da placa, a rota sem decodificador de frame ID liga CSIS0 ao WDMA2 por `0x1702041c`. O DTB recompilado contém VC0 em `0x170c3000`, bloco comum do canal em `0x170c3400`, topo WDMA em `0x170c0000`, SPI 190 e reset da PHY em `0x17020500`. O driver anuncia Bayer GRBG conforme `is-cis-2ld.c`.

Comparação literal dos arrays A2, A3 e 2016×1512 com o setfile Samsung aprovada. Um teste no host executou a função C de escrita contra um adaptador simulado, conferindo cada endereço, valor, ordem de byte e pausa. A3 transmitiu 5660 palavras em 90 mensagens de burst no limite padrão. Passaram dez limites de tamanho, erro do adaptador, transferência curta e limite insuficiente. O modo escreve `0x0310 = 0x0156` e o driver lê o PLL antes do stream-on. Os 17 testes de `python3 checks/test-build-recipes.py` passaram.

## Ensaio físico com 0120

`fastboot boot` iniciou a imagem UFS de 24.532.992 bytes com SHA-256 `23bc5266e8c5413b5c7fe1f708148fbd0ba0dc7ac4770933ce8291577d1ca05f`. A imagem de retorno 0119 permaneceu no slot. O grafo apresentou os dois links habilitados. O formato anunciado foi `pgAA`, stride 2528, sizeimage 3822336. O sensor escolheu A3. O primeiro STREAMON retornou ETIMEDOUT e `/tmp/test.raw` teve zero bytes. HSI2C registrou quatro timeouts TX em `0x10` com `int_status=0`, `trans_status=0x000a0008`. O driver parou no setfile global, antes do PLL e do stream-on. O encerramento também registrou `Power domain CSIS disable failed`.

## Correção de seguimento 0121

O DT anterior usava a variante AutoV9 com FIFO de 64 bytes para o controlador em `0x10580000`. O driver I²C da Samsung usa `EXYNOS5_FIFO_SIZE=16`. O 0121 seleciona 16 para esse controlador, preserva o cálculo de timing e inclui tamanho e posição no diagnóstico de falha de burst. O build incremental produziu imagem UFS de 24.532.992 bytes, SHA-256 `385a737b38c08cb6f26fadae51ffe2390fb9e5ab9e8679cce03a18bb9a658952`. O kernel e DTB correspondem byte a byte aos incorporados no uniLoader. Os 489 arquivos do pacote de módulos e índices são idênticos aos enviados para o 0120.

O fastboot iniciou o 0121 temporariamente. O DT em execução confirmou o novo compatible de HSI2C. O log ao vivo do segundo ensaio registrou A3 carregada em 2,12 s, modo 2016×1512, PLL `0x0156` e escrita de stream-on concluída. Após 12 s o arquivo ainda tinha zero bytes. CSIS contou um frame VC0, o DMA indicou `0x11` (início de linha e frame), nenhum IRQ WDMA e nenhum erro DMA. O CSIS acumulou 912367 interrupções. O domínio CSIS voltou a reportar falha de desligamento. Os 489 arquivos do pacote de módulos ficaram idênticos aos instalados no telefone.

O 0122 antecipa o preparo do WDMA ao stream-on, seleciona o caminho paralelo nos dois lados, configura os pacotes PDAF e embedded previstos no modo Samsung e mascara as fontes de IRQ do link. Somente o IRQ de fim de frame do WDMA entrega buffers ao vb2.
