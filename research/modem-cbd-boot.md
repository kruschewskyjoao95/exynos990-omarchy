# S5123: como o LineageOS carrega o firmware principal (marco 4)

Levantamento de 19/11/2026. Fontes:
- **[código]** kernel LineageOS `97369af7`, `drivers/soc/samsung/cpif/`;
- **[vendor]** partição `vendor` deste aparelho, lida da `super` (`sda26`, ext4 em +5602 MiB, 1380 MiB), só leitura;
- **[strings]** saída de `strings` do binário `cbd`.

Nenhum código do binário foi copiado. Ele fica fora do git.

## Linha de comando ([vendor] `etc/init/init.baseband.rc:19`)

```
service cpboot-daemon /vendor/bin/cbd -d -t s5100 -P by-name/radio -bs -me -B umts_boot0 -D umts_ramdump0 -n /mnt/vendor/efs
```

`cbd`: 156.944 B, ELF aarch64 Android 30, SHA-256 `c94168597aa426b245f4bf4e1e89911768318ea95f41c22662058ec39961b753`.

## Divisão kernel × `cbd` ([código])

- `IOCTL_LOAD_CP_IMAGE` → `cpboot_spi_load_cp_image()`: um `spi_sync` cru do BOOT. Reproduzido no marco 2.
- `IOCTL_START_CP_BOOTLOADER(NORMAL)` → `start_normal_boot()` → `link_start_normal_boot()` (zera filas e grava o magic de boot), `check_cp_status()` (espera `CP2AP_WAKEUP`) e `register_pcie()` → `s5100_poweron_pcie()` (`AP2CP_WAKEUP=1`, RC on, S2MPU `hsi2` RW para o `cp_shmem`, doorbell `int_pcie_link_ack`). A parte de PCIe foi reproduzida no marco 3.
- **O firmware principal não passa por ioctl.** O `cbd` escreve as mensagens do protocolo de boot em `/dev/umts_boot0` (`bootdump_write()`, quadros SIPC5 na fila legacy da memória compartilhada, avisando o CP por doorbell PCIe).
- `IOCTL_REQ_SECURITY` → `security_req` só existe para `LINKDEV_SHMEM` (`link_device.c:3727`). No S5123 (`LINKDEV_PCIE`) **não há SMC de verificação no AP**. As mensagens "security check fail for TOC/VSS" e "secure err: Invalid Main image" [strings] indicam verificação feita pelo próprio CP ou relatada por ele.
- `IOCTL_COMPLETE_NORMAL_BOOTUP` → `complete_normal_boot()`: espera `init_cmpl`, liga o L1.2 e as IRQs `phone_active`/`cp2ap_wakeup`, e passa a `STATE_ONLINE`.

## Protocolo de boot "STD UDL" ([strings], nomes de funções e mensagens)

- Sequência: `std_boot_load_cp_bootloader` (BOOT pelo SPI, "BOOT link SPI"), depois "main PCIE link" → `std_boot_load_cp_image` / `std_boot_dload`.
- Para cada estágio da TOC: `std_udl_stage_start` (falha reportada como "START fail (req:0x%X exp:0x%X)"), `std_dl_send_bin`, `std_dl_send_crc` e `std_udl_stage_done` ("DONE fail (req:0x%X exp:0x%X)").
- Funções auxiliares: `std_udl_req_resp`, `std_ul_rx_frame` ("[step %d] cmd 0x%X != exp 0x%X"), `std_ul_recv_info`, `std_ul_recv_data` e `std_udl_poll`.
- Log de cada estágio: "stage=%u, name:%s b_off=0x%08x, m_offset=0x%08x b_size=0x%08x", com campos que batem com a TOC do `radio` (`checks/modem-s5123.md`).
- NV: `%s/nv_data.bin` dentro de `-n /mnt/vendor/efs`. Se não existir, usa `create_empty_nv`.
- Fim: "Boot up process done!!!", propriedade `vendor.cbd.boot_done`, arquivo `cp_boot_done_%s`.

## O que falta para um carregador aberto

1. **Transporte no kernel**, portado do `cpif`: a região `cp_shmem` (IPC de 8 MiB, MSI), a fila legacy com quadros SIPC5, o doorbell PCIe e o nó `umts_boot0`. Também a liberação da S2MPU `hsi2` para o CP ler e escrever na RAM do AP, por HVC.
2. **Formato das mensagens STD UDL:** códigos de comando, `req`/`exp` de cada estágio, layout de cabeçalho e CRC. Exige desmontar o `cbd` só para interoperar, ou achar descrição pública. O ShannonRE/ShannonBaseband cobre o firmware do CP, não este protocolo, até onde foi visto.
3. Um carregador aberto que leia a TOC do `radio` e o `nv_data.bin` do `efs` e percorra os estágios.

## Fontes públicas encontradas (19/11/2026)

- **Scion-Project `drivers/modem/hakios.shannon.c`** ([PR #301](https://github.com/Scion-Project/scion-kernel/pull/301)), arquivo **MIT-0**: bring-up do Shannon *integrado* do Galaxy S9 (Exynos 9810, ss360ap) sem Android.
  - Boot por memória compartilhada mais SMC `0x82000700` na EL3. **Não é o nosso caminho de boot**: o S5123 usa SPI e PCIe.
  - Handshake do bootloader no canal 215: `0x900D`→`0xA00D` e `0x9F00`→`0xAF00`, em quadros `{0xfc, 215, 8, 0, word}`.
  - Depois do boot: `INIT_START`, tabela de anéis, `PIF_INIT_DONE`, `PHONE_START` (mensagem: bit 7 válido, bit 6 comando, bits 5:0 com 1/2/8/0xD/7/9).
  - Quadro SIPC5: `0xF8` (bit 2 = padding), canal e comprimento de 16 bits com o cabeçalho incluído.
  - SIM e registro na rede.
  - PDP pelo IPC Samsung, grupo `0x0D` (número 1 "set"; resposta geral `0x8000`; o CP devolve `0x0D/0x09` e `0x0D/0x10`).
  - Dados: canal 10 = contexto 1, interface `pdp_ip0`.
  - **Serve de referência para as etapas de IPC, rádio e dados.**
- **tonyg, `qnd_cbd.py`/`qnd_ril.py`** ([gist](https://gist.github.com/tonyg/4ea14f4dfe414422c0648c6e0a8bcb5d)), Galaxy S7, sem licença declarada, então só como referência de fatos.
  - Boot pelas ioctls do kernel Samsung (memória compartilhada) e handshake `0x900d`/`0x9f00` em `umts_boot0`.
  - Cabeçalho IPC de 7 bytes `len16, msg_seq, ack_seq, main_cmd, sub_cmd, cmd_type`.
- Contexto: [ARM Ninja, S6 modem](http://arm.ninja/2016/03/04/reverse-engineering-samsung-s6-modem/), [Comsecuris, Breaking Band](https://comsecuris.com/slides/recon2016-breaking_band.pdf), [Black Hat 2020, FirmWire](https://i.blackhat.com/USA-20/Wednesday/us-20-Hernandez-Emulating-Samsungs-Baseband-For-Security-Testing.pdf).

## Escuta do bootloader do S5123 (`packaging/modem/cp-boot-listen.py`, kernel #17)

IPC preparado como `init_legacy_link()`/`link_start_normal_boot()` (magic `BOOT`, `access=1`, filas zeradas), mais BOOT por SPI, link PCIe e doorbell `pcie_link_ack` (14). **O CP não escreveu nada em 6 s**: filas RX vazias e `cp2ap_msg` intacto. Coerente com o STD UDL, em que o AP fala primeiro (`std_udl_stage_start`). Para conhecer a primeira mensagem é preciso o comportamento do `cbd`.

No `cbd`, as referências às strings ficam em `.rodata` com deslocamento entre arquivo e memória: `std_udl_req_resp` é referenciado em `0x16a8c` por `adrp 0x7000` + `#0xe40`. A análise estática é viável, mas longa.

## Observação do `cbd` real (19/11/2026, kernel #17, sem flash)

Ferramentas, todas em `packaging/modem/`:
- `cuse-umts.c`: `/dev/umts_boot0` e `/dev/umts_ramdump0` em CUSE, com as ioctls do `cpif` mapeadas para GPIO, spidev, filas IPC por `/dev/mem`, `ap2cp_msg` + doorbell e `relink`. Faz trace hexadecimal em `/run/cbd-trace.log`.
- `cbd-props.c`: `LD_PRELOAD` freestanding (sem libc, carrega no bionic) que responde `property_get`/`set`.
- `cbd-observe.sh`: chroot Android com `system`, `vendor` e o APEX `com.android.runtime` montados ro a partir da `super`. RADIO e EFS entram como **cópias** em tmpfs (o `cbd` roda como `radio` e usaria O_RDWR).

O que o `cbd` faz, observado:
1. Espera `vendor.cbd.rfs_check_done` começar com `'1'` (50 × 100 ms, `0x1c640`).
2. `NV validation done`, TOC com `max_stage: 7` e `build_std_dload_control` com estágios 0–5 (TOC, BOOT b_size 0x320, MAIN 0x2ee7360, APM, VSS e NV 0x100000).
3. `POWER_ON` → `LOAD_CP_IMAGE` (`size=64400`, `m_off=b_off=mode=len=0`; a imagem começa por `2e 00 00 ea`, um branch ARM) → `START_CP_BOOTLOADER(mode 0)`.
4. **Primeira mensagem STD UDL: `write(umts_boot0, 00 91 00 00)` (`0x9100`), esperando `0xA100`.** Sem resposta, desiste em ~30 s e recomeça.

Transporte, achados no aparelho:
- **O doorbell só responde no endereço de barramento `pci_db_addr = 0x14d60000`.** Com o BAR0 do EP em `0x14d60000` (readback `0x14d00004`), ler a CPU em `0x14060000` dá `0x0`. Em qualquer outro BAR0 (`0x14f00000`) ou em BAR0+0, dá `0xffffffff`, que é falha para o `s51xx_pcie_send_doorbell_int()`.
- O Samsung desliga o BAR0/ROM do root port (`dbi+0x100010`/`0x100030 = 0`, `exynos_pcie_setup_rc()`), deixando a janela começar em `0x14000000` (barramento `0x14d00000`). No nosso kernel o BAR0 do root port ocupa essa faixa. **A corrigir no 0141/0142.**
- O root port vinha com `BusMaster-`; ligado por `setpci`.
- IOCC (`exynos_pcie_rc_set_iocc`) aplicado: DBI `0x8e8 = 0x10101010` e SYSREG_HSI2 `0x704 = 3`.
- **Bloqueio atual:** mesmo com doorbell, `ap2cp_msg = 0x81`, Bus Master e IOCC, o CP **não consome a fila RAW TX** (`tail` em 0) e não escreve nada na IPC. Velocidade Gen4 ou Gen1 não muda. A hipótese seguinte (não testada) é que falta o MSI: o `exynos_pcie_rc_poweron()` inicializa o MSI do RC (`cp_msi_rmem` em `0xf6200000`) antes do uso. Também pode faltar outro passo do `rc_poweron()`/`s51xx_pcie` que informe ao CP onde fica a memória do AP.

### Retomada no kernel #17

- Por SSH, em leitura, o log preservado em `/run/cbd-out.log` mostrou `vendor.cbd.rfs_check_done -> table` com `1`, `persist.vendor.cbd.debug_cp_opt -> default` com valor vazio e `sys.shutdown.requested -> default` com `0`. Um teste ARM64 do `property_get()` em QEMU confirmou os três valores, comprimentos e rótulos. O trace preservado mostra que o daemon abriu `umts_boot0`, enviou 64.400 bytes pelo SPI e chegou ao primeiro `0x9100`, com `tail=0` e sem resposta em 30 s. O `Permission denied` já havia sido superado no ensaio do Claude.
- Após o ensaio, `lspci -Dvv -s 0001:00:00.0` mostrou BAR0 do root port em `0x14000000` (1 MiB) e janela da bridge `0x14200000–0x147fffff`. Essa janela exclui `0x14060000`, endereço CPU usado pelo CUSE. Gravar o BAR0 do endpoint pela configuração PCIe não ajusta a janela da bridge. O valor `doorbell 0` no trace registra o valor escrito, sem confirmar que a transação chegou ao modem.
- O patch `0143` reaplica as duas máscaras de BAR do `exynos_pcie_setup_rc()` do LineageOS `97369af7` depois do reset do GEN4_1. O driver e o `Image` ARM64 compilaram em staging com GCC 14.2.0 (`Image` SHA-256 `1e11d76da99c56dc9b55fb363070b1e64d166ff2c4d7f20c0a0103fcae691405`). No próximo boot de teste, conferir que o BAR0 do root port deixou de ocupar o primeiro MiB e que a janela da bridge inclui `0x14060000` após `relink`. O avanço de `RAW TX tail` após `0x9100` confirma que o CP consumiu a mensagem. A resposta esperada é `0xA100`. MSI permanece uma hipótese em aberto, pois o observador consulta a fila RX por polling.

### Ensaio temporário no kernel #18 (`0143`)

- `fastboot boot` iniciou `r8s-ufs-0143.img` (24.532.992 B, SHA-256 `2697dd1aca32b613109a67811a540209878b335c331e266afae47d33a786a0d0`) com o Arch existente. uniLoader `2418e06`, mkbootimg `d2bb0af` e DTB do kernel #17, idêntico ao da árvore do build #18. A imagem foi extraída e comparada com os componentes do empacotamento. Sem flash.
- Antes do relink o BAR0 e o ROM BAR do root port não apareceram no `lspci`. Com o endpoint ativo, `lspci` mostrou janela `0x14000000–0x141fffff` e o BAR0 do endpoint retornou `0x14d00004`. O endereço CPU `0x14060000` ficou dentro da janela. O endpoint ainda reportou `MSI: Enable-`.
- O `cbd` validou NV, abriu CUSE e enviou `0x9100` três vezes. Amostra da região IPC durante a espera: `RAW TX head=8`, `tail=0`, `RAW RX head=tail=0`, `ap2cp_msg=0x81`, `cp2ap_msg=0`. O ensaio de 90 s terminou por timeout (`124`), sem `0xA100`. Após a limpeza, o endpoint e os processos `cbd`/CUSE saíram, e o Wi-Fi permaneceu conectado no domínio PCIe 0000. A correção da janela foi confirmada, e o firmware principal continua bloqueado no primeiro comando STD UDL.

### Firmware principal confirmado no kernel #18

- Configuramos o alvo MSI do root port e do endpoint para `0xf6200000`, como no LineageOS `97369af7`. O endpoint passou a `MSI Enable+`, quatro mensagens, dados `0`. A entrega de IRQ ao host ficou desabilitada (`DBI 0x828 = 0`) e o CUSE continuou consultando a fila RX. Em duas tentativas o CP respondeu `0xA100` em 3–4 ms e aceitou a TOC. A leitura de retorno do doorbell deu `0`.
- A TOC revelou o segundo bloqueio. O quadro de 820 B foi consumido até `tail=832`, enquanto o CUSE escreveu o quadro seguinte em `head=828`. `sipc5_calc_padding_size()` no LineageOS alinha por `BITS_PER_LONG / 8`, oito bytes em ARM64. Com quatro bytes de preenchimento neste quadro, `head` e `tail` voltaram a coincidir. O código aplica o mesmo alinhamento à leitura e à escrita.
- Em dois ensaios com MSI e alinhamento corrigidos, o `cbd` completou os estágios, recebeu `0xAF00` em resposta a `0x9F00` e saiu com código 0. No segundo ensaio, usando o código versionado do CUSE, `phone_active` passou de inativo a ativo dentro de 1 s e permaneceu ativo nas quatro amostras seguintes. O teste de alinhamento no host conferiu os offsets 828/832 e quadros já alinhados. Depois das amostras, o roteiro desligou o CP.
- O `COMPLETE_NORMAL_BOOTUP` do CUSE registra `cp2ap_msg=0x83` e retorna sucesso. O `complete_normal_boot()` do LineageOS espera `init_cmpl`, sinalizado no caminho que processa `PHONE_START`. Falta implementar e validar o handshake IPC em operação normal, o registro na operadora e a interface de dados. O êxito do carregamento e `phone_active` estabelecem o boot do firmware.

### Transição de BOOT para IPC no kernel #18

- Observação passiva em `/dev/mem`: 27 ms após o retorno do `cbd`, `cp2ap_msg` mudou de `0x83` para `0xc1` (`CMD_INIT_START`) e ficou nesse valor por 10 s. As filas de boot estavam vazias e `magic=BOOT`, `access=1`. O comando real do CP confirma a entrada na sequência `cmd_init_start_handler()` do cpif.
- No LineageOS `97369af7`, esse handler inicializa PKTPROC e SBD antes de enviar `PIF_INIT_DONE` (`0xcd`). O AP espera `PHONE_START` (`0xc8`) antes de trocar o magic para `0xaa`. O envio posterior de `INIT_END` (`0xc2`) depende de `rild_ready()`, que para SIPC requer FMT e RFS abertos.
- Dois ensaios em RAM escreveram tabelas experimentais de SBD e PKTPROC seguindo a geometria do DT r8s e enviaram `0xcd` somente após `0xc1`. O doorbell teve readback `0x0`. A repetição, com atraso de 1 s e stores ordenados, terminou com `cp2ap_msg=0xc1` e fila PKTPROC `fore=3173`, `rear=0`, sem observar `0xc8` em 8 s. Os testes validaram os limites locais das tabelas e o transporte até `INIT_START`. Falta validar que o CP leu e aceitou os descritores, e isolar a sinalização de IPC depois do boot. Protótipos em `out/validation/modem-0143/ipc-probe/`.

### `PHONE_START` recebido no kernel #18 (19/11/2026, sem flash)

- **Causa do bloqueio (observado no código):** o cpif não escreve o número da interrupção puro no doorbell. `link_device.c:4064` define `intval_ap2cp_msg = int_ap2cp_msg + DOORBELL_INT_ADD`, e `include/legacy.h:16` define `DOORBELL_INT_ADD 0x10000`. O `pcie_link_ack` segue a mesma regra (`modem_ctrl_s5100.c:1404`). Nossas ferramentas escreviam `0`. O carregador de boot aceitou os quadros mesmo assim, provavelmente por polling. O firmware principal ignorou o `PIF_INIT_DONE`.
- **Testado neste aparelho:** `packaging/modem/ipc-handshake.py` sobe antes do `cbd`, espera um `0xc1` novo e escreve as tabelas SBD e PKTPROC de `create_sbd_mem_map()`/`init_sbd_link()` e `pktproc_create()`/`pktproc_init()`. Em seguida grava `ap2cp_msg=0xcd` e o doorbell `0x10000`.
  - Com o doorbell `0`, a resposta saiu em 0,6–1,0 ms, mas o CP não alterou nenhuma palavra da IPC ou do PKTPROC em 10 s. O link ficou em L0 (`ltssm=0x11`), com MSI `Enable+` e `phone_active` ativo.
  - Com o doorbell `0x10000`, o readback foi `0x10000`, e `cp2ap_msg` passou de `0xc1` a `0xc8` (`CMD_PHONE_START`) 75–78 ms depois, em dois ensaios seguidos.
  - O CUSE com o doorbell `0x10000` também conduziu o boot inteiro: 26913 quadros, `cbd` rc 0.
- **Próximo passo (proposta):** o `cmd_phone_start_handler()` chama `init_legacy_link()` (magic `0xaa`). Ele só envia `INIT_END` (`0xc2`) quando `rild_ready()` é verdadeiro, ou seja, com FMT (`umts_ipc0`, canal 235) e RFS (`umts_rfs0`, canal 245) abertos. Depois disso a pilha precisa de transporte SBD para RIL e RFS, e de PKTPROC para os dados. Registro na operadora e `rmnet` ainda não foram testados.

### Operação normal: `INIT_END` e primeiras mensagens IPC (19/11/2026, kernel #18, sem flash)

- **Testado neste aparelho:** depois do `PHONE_START`, `ipc-handshake.py` reproduz `init_legacy_link()`: zera o magic, o acesso e as filas legadas, depois grava magic `0xaa` e acesso `1`. Em seguida envia `INIT_END` (`0xc2`, doorbell `0x10000`).
- **Resposta do CP:** 1,4 s depois, `cp2ap_msg` passou a `0x83` e o ponteiro de escrita do anel SBD DL do canal 235 (`umts_ipc0`, FMT) foi a 4, depois a 6 e a 10. O roteiro consumiu os dez quadros e avançou o ponteiro de leitura.
- **Formato dos quadros:** cada um tem cabeçalho SIPC5 (`f8 eb <len16>`) seguido do cabeçalho IPC Samsung (`len16 mseq aseq main sub type`). Exemplos:
  - `13 05 03 … "AST_POWERON\r\n"`;
  - `01 01 03` (PWR / PHONE_PWR_UP / NOTI);
  - `0d 0f 03`, `05 11 03`, `05 0c 03`, `05 10 03`, `05 07 03`, `01 07 03`.
- **Campo de tamanho:** `buff_len_array` traz o canal nos bits 16–23 (`0x00eb001d` = canal 235, 29 B).
- **Após 20 s:** `cp2ap_wakeup` ficou inativo, com `phone_active` ativo. Nenhum quadro apareceu no RFS (canal 245) nem nos canais de dados.
- **Próximo passo (proposta):** responder às mensagens IPC (energia, SIM e rede) por um daemon nativo que use o transporte SBD. Referência: Scion `hakios.shannon.c` (MIT-0), que implementa a mesma família IPC no Shannon do Galaxy S9, com SIM, registro e PDP `0x0D`. Os dados virão depois, por PKTPROC.

### Registro na rede pelo daemon nativo (19/11/2026, kernel #18, sem flash)

- **Testado neste aparelho:** `packaging/modem/s5123-ril.py` sobe antes do `cbd` e faz o handshake (`INIT_START` → `PIF_INIT_DONE`, `PHONE_START` → `init_legacy_link` + `INIT_END`). Depois fala IPC Samsung no anel SBD do FMT, seguindo a lógica de Scion `hakios.shannon.c` (MIT-0):
  - baixo consumo na fila antes do `INIT_END`;
  - versão;
  - modo normal;
  - retorno ao baixo consumo antes de desligar.
- **NV:** os pedidos NV do RFS são atendidos por uma cópia em RAM do `nv_data.bin`, nunca a EFS real. Neste ensaio o CP não fez nenhum pedido RFS.
- **Resultado:**
  - versão `G780FXXSOFYJ1` / `REV0.3`;
  - modo normal aceito (resposta geral `0x8000`, PHONE STATE 2);
  - SIM `0x82` (READY), depois `0x83` (phonebook ready);
  - **REGISTRATION state 2 (HOME)**, tecnologia 4, nos domínios 2 e 3;
  - rede servidora `72402`;
  - sinal de 4 barras, -74 a -80 dBm.
- **Escritas não alinhadas:** em `/dev/mem` com `O_SYNC` (memória de dispositivo), uma cópia com `memcpy` de tamanho ímpar dá `SIGBUS`. O daemon copia em palavras alinhadas.
- **Mensagens retidas:** entre 12 s e 99 s nenhuma mensagem DL chegou. Todas foram entregues juntas logo depois do próximo pedido do AP. Hipótese (proposta): o CP espera `pcie_link_ack` (doorbell `0x1000e`) depois de subir `cp2ap_wakeup`, como em `s5100_poweron_pcie()`. Sem isso, ele segura as mensagens.

### Entrega das mensagens do CP e economia de energia do link (19/11/2026, kernel #18, sem flash)

- **Com o link sempre ligado:** o CP só entrega notificações (registro, sinal) depois de um quadro UL do AP. Um doorbell vazio (`MSG_DATA` sem quadro) ou uma leitura do BAR não basta. O CP também nunca sobe `cp2ap_wakeup` sozinho. Com uma consulta de registro (`08 05` GET) a cada 2 s, as notificações chegam em tempo real: HOME em 3G (UMTS, tecnologia 4) 2 s depois do modo normal, e o sinal é atualizado. Esse é o modo padrão do `s5123-ril.py`.
- **Sequência Samsung (`R8S_PCIE_PM=1`, testado):**
  1. o CP baixa `cp2ap_wakeup`;
  2. 30 ms depois, o AP tira o Bus Master e o MSI do EP, coloca-o em D3hot e baixa `AP2CP_WAKEUP`;
  3. o AP faz `PME_Turn_Off`: ack recebido e LTSSM `0x15` (L23_READY);
  4. o link desliga (PERST);
  5. 210–250 ms depois, o CP pede o link sozinho (`cp2ap_wakeup` 1);
  6. o AP religa (`relink 1`, ~200 ms; o EP volta em Gen3 x2): COMMAND do root, IOCC, BAR0, MSI e `pcie_link_ack`, repetido em +0, +50 e +200 ms.
- **Resultado do ciclo:** depois dele, o CP não consome mais o anel FMT UL (`rp=2`, `wp=3`) e fica mudo. Root e EP estão sem erro AER, e o EP com BusMaster+. O EP marcou `>TAbort+` uma vez. Falta acertar a restauração (ordem de `pci_restore_state`, MSI e BME). Até lá, o link fica ligado.
- **Detalhe da resposta GET de registro:** ela traz `domain 0 state 1`, um formato diferente da notificação. Isso não indica perda de registro.

### Conexão de dados 3G (UMTS/HSDPA) na TIM (19/11/2026, kernel #18, sem flash)

- **Sequência que funcionou (testada):** os layouts vêm de `IpcProtocol41Data` na `libsec-ril.so` do vendor. Foram lidos só para entender o protocolo; nada do binário está no repositório.
  1. PS attach `0D 03` SET com os dados `01 00 00` (mensagem de 10 B);
  2. definição do contexto `0D 01` SET: 149 B; `[enable 1, cid 1, tipo 2 (IP), APN…]`;
  3. ativação `0D 04` SET: 248 B; `[estado 1, cid 1, flags u32, usuário[100], senha[100], …, auth no offset 238]`.
- **Sem o PS attach:** o CP aceita definição e ativação (`0x8000`), mas avisa na hora `0D 10` status 3 (desabilitado), com causa 0.
- **Com o PS attach:** 4 s depois chegam `0D 09`, com o IPv4 do contexto (CGNAT `100.x`) e o DNS da operadora, e `0D 10` status 1 (ENABLED). A TIM não pediu usuário nem senha.
- **Plano de dados:**
  - UL: IP cru no anel SBD do canal 11 (`QOS_NORMAL`), com `buff_len = len | 10 << 16` (canal do `rmnet0`).
  - DL: chega pelos anéis SBD multipdp (canais 10/11), não pelo PKTPROC neste ensaio.
  - O `s5123-ril.py` cria a `rmnet0` (TUN) com o IP recebido e a rota padrão de métrica 900, abaixo do Wi-Fi.
- **Resultado:**
  - handshake TCP completo, e o anúncio de roteador IPv6 chegou;
  - `curl --interface rmnet0 http://example.com` → HTTP 302, 153 B, em 1,8 s;
  - 76 pacotes subiram e 40 desceram; o anel UL foi consumido (`rp=wp`).
- **Pendências:**
  - HTTPS falhou em 0,4 s;
  - ping ICMP (1.1.1.1 e 8.8.8.8) sem resposta;
  - o contexto caiu com causa 2 (desativação regular) quando o daemon pôs o rádio em baixo consumo no fim.
- **Pacotes rastreados pelo daemon (`R8S_PKTLOG`):** SYN e SYN-ACK passam e o ACK sobe. Depois do primeiro segmento com dados chega RST da rede, e alguns destinos nem respondem ao SYN. Nenhum ICMP desce. Com MTU 1280 o comportamento é o mesmo.
- **Todo HTTP é redirecionado:** `example.com` e `neverssl.com` devolvem `302 Found`, `Location: http://wcad.tim.com.br/`. Esse é o portal de bloqueio da TIM (linha sem pacote de dados ativo ou franquia esgotada, a confirmar pelo proprietário).
- **Conclusão (observado):** o plano de dados do Linux funciona de ponta a ponta até a rede da TIM. O que sobra está do lado da operadora/linha. A falta de PCO/IPv6 (pedimos só IPv4) não foi descartada.

### Correção e serviço permanente (19/11/2026)

- **Correção:** a tecnologia `4` do registro é UMTS (`IPC_NET_ACCESS_TECHNOLOGY_UMTS`, libsamsung-ipc `net.h`), e `0D 0C = 01` é HSDPA. O aparelho está registrado em 3G, não em LTE como anotei antes. O 4G depende de um passo ainda não feito: modo de rede LTE ou perfil de attach `0D 14`.
- **Testado:** `r8s-modem.service` (instalado por `packaging/modem/install-modem.sh`, habilitado no boot) roda `s5123-modem-run.sh`. Ele mantém o `s5123-ril.py`, que grava `/run/s5123/status.json` a cada 2 s, por exemplo: online, SIM pronto, home, TIM, `3G H`, 4 barras, -62 dBm. `systemctl restart` põe o rádio em baixo consumo, desliga o CP e o sobe de novo.
- **Barra:** o widget `r8s.cellular` (`packaging/modem/omarchy-plugin/`, instalado em `~/.config/omarchy/plugins/r8s-cellular` porque esta versão do Omarchy espera hífen na pasta) lê esse arquivo. O widget carregou sem erro de QML. Falta conferir na tela.
- **Modo avião e dados móveis (testado):**
  - `r8s-modem-ctl airplane on|off` e `data on|off` gravam `/run/s5123/request`. Só o usuário da área de trabalho e o root podem escrever, e o daemon aceita apenas `airplane=0|1` e `data=0|1`.
  - O daemon guarda a escolha em `/var/lib/r8s-modem/prefs.json`.
  - Avião: desativa o contexto, remove a `rmnet0` e põe o rádio em baixo consumo (`01 07 = 01 00`). O registro some.
  - Saindo do avião: modo normal; registrado de novo e com dados em 8 s.
  - Dados desligados: `0D 04` com estado 0 desativa o contexto, e o CP confirma com `0D 10` status 3.
  - O APN vem da operadora registrada (TIM → `timbrasil.br`), ou de `R8S_APN`.
  - O widget `r8s.cellular` abre um cartão com as duas chaves. Ele só roda as linhas de comando fixas do `r8s-modem-ctl`.
