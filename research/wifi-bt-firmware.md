# Firmware próprio do aparelho para Wi-Fi e Bluetooth (QCA6390)

Agente `wifi-bt-firmware`, 2026-11-17. Nada aqui foi **testado no aparelho**. Marcações:
**[código]** observado no código/arquivo, **[autor]** relatado pelo autor do port,
**[inferência]** dedução nossa a partir de evidência, **[proposta]** sugestão nossa.
Sem patch de kernel e sem edição de scripts de build. Firmware proprietário só em
diretórios ignorados pelo git (`blobs/`, `out/`).

## Resumo

| Pergunta | Resposta |
|---|---|
| Qual `bdwlan` vale para o aparelho | `bdwlan.elf`. `.elf1`/`.elf2` são variantes de antena única para teste de fábrica [inferência forte] |
| Board/chip id pedido pelo ath11k | `bus=pci,qmi-chip-id=0,qmi-board-id=255` (provável); 4 é a única outra possibilidade [inferência] |
| Gerar `board-2.bin` com o BDF do aparelho | Feito: `out/agents/wifi-bt-firmware-fw/ath11k/QCA6390/hw2.0/board-2.bin` |
| `amss`/`m3` iguais? | Não. O vendor tem `amss` de outro ramo e mais novo e um `m3` mais antigo |
| Firmware BT do port = vendor? | Não. Mesma ROM (0x0200), patch e NVM diferentes |
| O NVM do aparelho resolve o BT? | Não deve resolver a dessincronização: o protocolo de download é o mesmo. Ajuda só na calibração de RF. A suspeita principal está no DT (UART sem RTS) |
| **Bloqueio para testar Wi-Fi** | O kernel embute os três arquivos do ath11k (`CONFIG_EXTRA_FIRMWARE`), e o firmware embutido tem precedência sobre o rootfs. Trocar arquivos no rootfs **não tem efeito** sem recompilar o kernel |

## Wi-Fi (ath11k)

### Seleção do BDF no Android
- [código] `lk/k/drivers/net/wireless/cnss2/qmi.c:461-503` (`cnss_get_bdf_file_name`): se o
  `board_id` do OTP (resposta QMI de capacidade) for `0xFF`, o driver pede `bdwlan.elf`, ou
  `bdwlan.elf1`/`bdwlan.elf2` quando `ant_from_macloader` vale 1 ou 2. Para outros ids, pede
  `bdwlan.eXX` ou `bdwlanXX.eYY`. O prefixo `qca6390/` vem de `pci.c:61`.
- [código] `ant_from_macloader` só é escrito por `/sys/wifi/ant` (`cnss2/debug.c:893-899`).
  No vendor, `macloader` é um script de 2 linhas (MAC e `boot_wlan`) e não escreve
  `/sys/wifi/ant`. Nenhum arquivo em `vendor/` referencia `.ant.info` além dos `chown` nos
  `.rc`.
- [inferência] O vendor só traz `bdwlan.elf*` e nenhum `bdwlan.eXX`. Como o Wi-Fi funciona no
  Android, o OTP deste chip deve responder `board_id = 0xFF`, e o arquivo de uso normal é
  `bdwlan.elf`.
- [código] As três variantes diferem em 9 bytes do BDF (offset relativo ao BDF, que começa no
  `.data` em 0x400): byte 10 (checksum), byte 24 (`01`/`02`/`03`), byte 32 (`f0`/`f4`/`f4`)
  e bytes 1060-1061 e 1200-1206 (`03` → `01` ou `02`). O padrão bate com "duas antenas" contra
  "só antena 1" ou "só antena 2" [inferência].

### O que o ath11k do port pede
- [código] Para QCA6390, `pci.c` não define `bdf_search = BUS_AND_BOARD` (só o WCN6855 define).
  O nome usado é `bus=pci,qmi-chip-id=%d,qmi-board-id=%d[,variant=%s]` (`core.c:1139-1145`), e
  `variant` vem só de `qcom,ath11k-calibration-variant` no nó DT do dispositivo PCI
  (`core.c:1072`). Depois o driver tenta o mesmo nome sem a variante e, por último,
  `board.bin` (API 1).
- [código] O `board-2.bin` do linux-firmware (blobs = host `linux-firmware 20261019`, sha256
  `4aa9f0fe…`) tem 4 entradas: `qmi-chip-id=0,qmi-board-id=255`, `…=4`, `…=255,variant=Xiaomi_Pad_5Pro` e
  `…_5G`.
- [inferência] O Wi-Fi funciona no port [autor], então o nome casou com uma entrada:
  `chip_id=0` e `board_id` igual a 255 ou 4. Pela lógica Samsung acima, é 255, ou seja, o port
  carrega hoje o **BDF genérico de referência da Qualcomm**, não o do S20 FE.
- [código] O ath11k registra os ids em nível info (`qmi.c:2270`):
  `ath11k_pci …: chip_id 0x0 chip_family … board_id 0xff …`. Esse é o primeiro passo de teste
  (só leitura de log).

### Comparação dos BDF
- [código] Os dois BDF usam o mesmo template: `.data` de 0xdb74 bytes, cabeçalho `01 00 04 04`.
  Em relação à entrada genérica 255, o `bdwlan.elf` da Samsung difere em **8400 de 56180 bytes
  (15%)**. Para comparação, as entradas 255 e 4 do linux-firmware diferem em 5237 bytes. É
  ajuste de placa real (tabelas de potência, front-end e antenas), não só metadados.
- [código] O ath11k aceita BDF em ELF: detecta `ELFMAG` e envia `ATH11K_QMI_BDF_TYPE_ELF`
  (`qmi.c:2433`), sem caldata para QCA6390. O `regdb.bin` do vendor não é usado
  (`supports_regdb = false` para QCA6390).

### `board-2.bin` gerado
Ferramenta `ath11k-bdencoder` do qca-swiss-army-knife, commit `6df4dae3` (clone em
`scratchpad/wifi/qsak`).
```
out/agents/wifi-bt-firmware-fw/src/board-2.json:
  names: "bus=pci,qmi-chip-id=0,qmi-board-id=255",
         "bus=pci,qmi-chip-id=0,qmi-board-id=255,variant=Samsung_r8s"
  data:  bdwlan.elf do vendor (sha256 9fe8b78f…)
saída: out/agents/wifi-bt-firmware-fw/ath11k/QCA6390/hw2.0/board-2.bin  sha256 d5a17699…
reproduzir: python3 -I qsak/tools/scripts/ath11k/ath11k-bdencoder -c board-2.json -o board-2.bin
```
O nome com `variant=Samsung_r8s` só seria usado se o DT ganhasse um nó PCI com
`qcom,ath11k-calibration-variant`. Sem isso, vale a entrada 255. O arquivo contém só a entrada
Samsung: se o `board_id` real for 4, nada casa e o ath11k falha ao carregar o BDF. Por isso o
passo 1 do plano de teste vem antes.

### amss / m3
| Arquivo | linux-firmware (port) | Vendor LineageOS |
|---|---|---|
| amss | `WLAN.HST.1.0.1-05266-QCAHSTSWPLZ_V2_TO_X86-1`, UUID de 2021-11-04, sha `8ab2a064…` | `amss20.bin`: `WLAN.HSTE.1.0.1.c7-00142-QCAHSTSWPL_V2_TO_LITE_R-1`, 2025-04-24, sha `e09d8e3c…` |
| m3 | build 2021/04/29, sha `1921d25e…` | build 2020/08/17, sha `1c1b0e57…` |

- [inferência] O amss do vendor é de outro ramo (`HSTE … LITE_R`, feito para o qcacld/cnss do
  Android). O do linux-firmware é o alvo "TO_X86" que a Qualcomm publica para o ath11k. Trocar
  o amss é mais arriscado e menos promissor que trocar o BDF. Se for testado, troque amss e m3
  **em par**.
- [código] `firmware/wlan/qcom_cfg.ini` é configuração do qcacld e não se aplica ao ath11k.
  Dado útil: o Android usa `gRuntimePM=0` (sem runtime PM no PCIe).

### Por que trocar arquivos no rootfs não basta hoje
- [código] `out/agents/kernel.config:1642`:
  `CONFIG_EXTRA_FIRMWARE="ath11k/QCA6390/hw2.0/amss.bin … m3.bin … board-2.bin"`.
- [código] `drivers/base/firmware_loader/main.c:757` consulta o firmware embutido antes do
  sistema de arquivos. O `build-arch-rootfs.sh:161-163` copia os mesmos arquivos para o rootfs,
  mas essa cópia nunca é lida.
- [proposta, não aplicada] Em `build-m1-kernel.sh` e na config, usar `CONFIG_EXTRA_FIRMWARE=""`.
  O `ath11k_pci` é módulo (`=m`) e carrega depois do rootfs, então o firmware no
  `/usr/lib/firmware` basta. A troca passa a ser cópia de arquivo + `modprobe -r/modprobe`.
  Antes, confirmar que o ath11k não entra num initramfs sem firmware (não verifiquei).

## Bluetooth (btqca / hci_qca)

### Nomes e versões
- [código] `btqca.c:761-787,848-850`: para QCA6390, `rom_ver = ((soc_ver & 0xf00) >> 4) | (soc_ver & 0xf)`
  dá `qca/htbtfw20.tlv` e `qca/htnv20.bin`. São os mesmos nomes do vendor, que também carrega
  esses dois arquivos (strings do `android.hardware.bluetooth@1.0-impl-qti.so`: `htnv20.bin`,
  `/vendor/firmware/`).
- [autor] O port usava o `qca/` do linux-firmware (`docs/FIRMWARE.md`). A versão exata não está
  fixada. O linux-firmware 20261019 do host traz:

| | linux-firmware (host 20261019) | Vendor LineageOS |
|---|---|---|
| `htbtfw20.tlv` | 210704 B, `BTFM.HST.2.0.0-00943-QCACHROM-1`, patch_ver 0x3ac0 | 211704 B, `BTFM.HST_EXT.2.0.0.c3.2-00158-QCACHROMZ-1`, patch_ver 0x7aae |
| cabeçalho do patch | ROM 0x0200, product 0x0010, **download_mode 3** | igual: ROM 0x0200, product 0x0010, **download_mode 3** |
| `htnv20.bin` | 5857 B, 53 tags | 6037 B, 53 tags, 18 tags diferentes (RF: 22, 36, 38, 39, 44, 62…) |
| NVM tag 17 (HCI/UART) | `151122002e00` | idêntica |
| NVM tag 2 (BD addr) | endereço padrão | idêntico (placeholder) |

- [código] As duas versões têm o mesmo `download_mode` (3 = sem VSE e sem CC por segmento) e a
  mesma tag de transporte. O driver segue o mesmo caminho de código com qualquer um dos pares.
  **Trocar firmware ou NVM não muda o protocolo em que o port dessincroniza.** O NVM do aparelho
  vale pelo ajuste de RF da placa e é o certo a usar depois que o download funcionar.
- [código] O rootfs Arch atual **não tem nenhum firmware `qca/`**: `build-arch-rootfs.sh:139-148`
  instala só `base …` e aborta se aparecer pacote `linux-*` além de `linux-api-headers`, o que
  bloqueia `linux-firmware`. O BT nem chegaria ao download no nosso rootfs.
- [código] O BD addr do NVM é o padrão de fábrica. `qca_check_bdaddr` vai marcar
  `HCI_QUIRK_USE_BDADDR_PROPERTY`, e o `hci0` fica "unconfigured" até receber um endereço
  (`btmgmt public-addr`). O endereço real está em `efs:/bluetooth/bt_addr` (o arquivo existe em
  `backups/efs.img`; não li o valor).

### Suspeita principal da dessincronização (fora do firmware)
- [código] DT stock (`rt.dts:161-167`, `uart@10840000`): `uart1-bus` com os 4 pinos `gpq0-0..3`
  na função 2 (RX, TX, RTS, CTS) e `samsung,rts-gpio-control`.
- [código] DT do port (`exynos990.dtsi:863`): `pinctrl-0 = <&uart1_bus_norts>`, só
  `gpq0-3, gpq0-1, gpq0-0`. O RTS do host (`gpq0-2`) não fica com a UART.
- [código] O `hci_qca` liga flow control (`hci_qca.c:1421`) e o `samsung_tty` ativa AFC com
  `CRTSCTS` (`samsung_tty.c:1575`), mas sem o pino RTS o host não consegue frear o controlador.
  A 3 Mbit/s, a FIFO RX de 256 B enche em cerca de 0,85 ms.
- [inferência] Bytes perdidos no RX quebram o enquadramento H4 e produzem exatamente "eventos
  inesperados" depois de centenas de segmentos. Isso combina com "974 events, then
  desynchronises" [autor] e explica melhor o problema que uma diferença de firmware.
- [proposta, candidato a patch 0106, não feito] Usar `pinctrl-0 = <&uart1_bus_single>` (os 4
  pinos, como no stock) no `bt_uart`. Antes, rodar o teste B2 abaixo, que não exige recompilar
  o kernel.

## Onde instalar para testar (só uso local, nunca no git)
Os arquivos estão em `out/agents/wifi-bt-firmware-fw/` (ignorado pelo git). As origens são
`blobs/r8s-device/vendor/root/firmware/`.

| Destino no rootfs | Origem | Observação |
|---|---|---|
| `/usr/lib/firmware/ath11k/QCA6390/hw2.0/board-2.bin` | `out/agents/wifi-bt-firmware-fw/ath11k/QCA6390/hw2.0/board-2.bin` | Só tem efeito com o kernel sem `CONFIG_EXTRA_FIRMWARE`. Guardar o original como `board-2.bin.linux-firmware` |
| `/usr/lib/firmware/ath11k/QCA6390/hw2.0/{amss.bin,m3.bin}` | vendor `qca6390/amss20.bin` → `amss.bin`, `qca6390/m3.bin` | Opcional, passo W4, em par |
| `/usr/lib/firmware/qca/htbtfw20.tlv`, `htnv20.bin` | vendor `htbtfw20.tlv`, `htnv20.bin` (raiz de `firmware/`, não `qca6390/`) | Para comparação A/B, ter também os do linux-firmware (`/usr/lib/firmware/qca/*.zst` do host, descomprimidos) |

[proposta] Para os scripts (não editados): (1) `CONFIG_EXTRA_FIRMWARE=""` no build do kernel.
(2) Em `build-arch-rootfs.sh`, copiar `qca/htbtfw20.tlv` e `htnv20.bin`, que hoje faltam, e,
com uma opção como `R8S_DEVICE_FW=1`, usar o `board-2.bin` Samsung e os arquivos `qca/` do
vendor no lugar dos genéricos.

## Plano de teste no aparelho (do mais seguro ao mais arriscado)
O firmware do QCA6390 vai para a RAM a cada boot e o chip não tem flash, então nenhum passo
grava nada no rádio. Para desfazer, basta repor os arquivos e recarregar o módulo ou reiniciar.

**Wi-Fi**
- W1 (só leitura, kernel atual): `dmesg | grep -E 'ath11k.*(chip_id|fw_version)'`. Confirmar
  `chip_id 0x0`, `board_id 0xff`. Se vier 4, o `board-2.bin` gerado precisa de mais uma entrada
  com `qmi-board-id=4`. Registrar também a linha de base: `iw dev wlp1s0 link`,
  `iw dev wlp1s0 station dump` (sinal, bitrate) e a contagem de `CTRL-EVENT-DISCONNECTED` e
  `r8s-netwatch` em `journalctl` durante N horas, no mesmo AP e na mesma posição.
- W2 (kernel recompilado sem `EXTRA_FIRMWARE`, firmware genérico no rootfs): repetir W1 para
  provar que só a origem do arquivo mudou.
- W3 (`board-2.bin` Samsung): `modprobe -r ath11k_pci; modprobe ath11k_pci`. Verificar que não
  aparece `failed to fetch board data`. Comparar sinal, taxa e quedas com W2. Testar 2,4 e
  5 GHz.
- W4 (opcional, mais arriscado): `amss.bin` + `m3.bin` do vendor, com o BDF Samsung. Pode falhar
  em QMI/WMI ou travar o firmware. Se travar o PCIe, reiniciar.
- Risco de RF: o BDF define limites de potência. O BDF Samsung é o que a placa usa no Android,
  então o risco é menor que o do genérico atual. Mesmo assim, não deixar o aparelho
  transmitindo sem acompanhar a temperatura no primeiro teste.

**Bluetooth**
- B1 (sem recompilar): instalar `qca/htbtfw20.tlv` e `htnv20.bin`, primeiro os do
  linux-firmware, depois os do vendor. Registrar até onde o download vai e o primeiro erro
  (`dmesg`). `CONFIG_DYNAMIC_DEBUG` está desligado na config, então os `bt_dev_dbg` não
  aparecem. Para o log por segmento é preciso recompilar com ele ligado.
- B2 (sem recompilar, testa a hipótese da UART): repetir com o parâmetro que já existe no patch
  0020 em velocidade baixa, `modprobe hci_uart oper_speed=115200` (download de ~210 KB leva uns
  20 s). Antes e depois, ler os contadores `oe:`/`fe:` da UART em
  `/proc/tty/driver/<driver samsung>`. Se o download terminar a 115200 e falhar a 3 M, ou se
  `oe` subir, a causa é perda de RX sem RTS, e o caminho é o DT (`uart1_bus_single`).
- B3 (precisa de patch de DT): `uart1_bus_single` em 3 M.
- B4: com o `hci0` de pé, `btmgmt --index 0 public-addr <endereço de efs:/bluetooth/bt_addr>`,
  depois `bluetoothctl scan on`.

## Riscos
- A troca de BDF muda a potência TX e o perfil de antena. É o BDF de fábrica desta placa, mas
  nunca foi testado com o amss do linux-firmware. Ver se o firmware o aceita (W3) antes de
  confiar nele.
- O `board-2.bin` gerado só cobre `board_id 255`. Se o id for outro, o Wi-Fi fica sem BDF. W1
  resolve isso antes.
- Tirar o `EXTRA_FIRMWARE` depende do rootfs ter os arquivos. Se faltarem, o Wi-Fi não sobe, e
  o console USB continua como caminho de recuperação.

## Perguntas em aberto
- `board_id` real (W1). Os offsets 24 e 32 do BDF são de fato antena ou chainmask? (não há
  documentação pública do template).
- Os 974 eventos de [autor] eram só do patch (868 segmentos de 243 B) ou já do NVM? Com
  `download_mode 3` o controlador não deveria responder por segmento. Ver o log de debug em B1.
- O amss "LITE_R" do vendor é compatível com o WMI do ath11k 6.12? Só W4 responde.
- Qual `htbtfw20.tlv` o autor do port usou de fato (Debian trixie `firmware-atheros`?). A versão
  não está registrada.

## Ferramentas e fontes
- Scripts de análise: `out/agents/wifi-bt-firmware-fw/src/bd2.py` (lista as entradas de um
  `board-2.bin`) e `qcabt.py` (lê o cabeçalho do TLV de patch e compara as tags de dois NVM).
- Kernel LineageOS `97369af7`, `drivers/net/wireless/cnss2/{qmi.c,debug.c,pci.c}`. Base do port
  `r8s-port-base`: `drivers/net/wireless/ath/ath11k/{core.c,qmi.c,pci.c}`,
  `drivers/bluetooth/{btqca.c,hci_qca.c}`, `drivers/tty/serial/samsung_tty.c`,
  `arch/arm64/boot/dts/exynos/exynos990{.dtsi,-pinctrl.dtsi}`.
- qca-swiss-army-knife `6df4dae3e2f5e4c2903f3cafd40996fc1b3639ce`.
