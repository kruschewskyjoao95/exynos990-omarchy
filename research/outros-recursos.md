# Viabilidade de outros recursos no kernel mainline do port (SM-G780F / r8s)

Agente `outros-recursos`. Só pesquisa: nada foi testado no aparelho, nenhum patch foi escrito, o telefone não foi acessado.

Marcações: **[código]** observado em `rt.dts`, dmesg, vendor ou kernel LineageOS 4.19 (`97369af7`); **[web]** relatado por terceiros, não verificado por nós; **[proposta]** nossa.

Estado base do port **[relatado pelo autor]**: `sources/port/docs/STATUS.md` lista "Cellular, cameras, NFC, fingerprint, sensors, haptics, GPS" como "not supported / not started". A página do postmarketOS para o r8s não pôde ser lida (redirecionou para wiki.nura.eco, que bloqueou com Anubis).

## Tabela-resumo

| Recurso | Viável | Esforço | Primeira prova mínima |
|---|---|---|---|
| 1a. Sensores atrás do hub SSP/BCM4773 | talvez | alto (semanas), e depende de blob | Com o kernel mainline, ligar `vdd_mcu_1p8` e o GPIO de reset, e ler por SPI o byte de status do MCU. Isso só prova que o bus funciona |
| 1b. Sensores fora do hub (`tcs3407` traseiro, grip `a96t356`) | sim (I2C direto) | baixo a médio | `i2cdetect` no hsi2c `0x109D0000`: o `tcs3407` deve responder em 0x29. Depois, driver IIO novo |
| 2. GPS (BCM4773) | não (sem caminho livre conhecido) | muito alto | Nenhuma prova razoável. Alternativa: GNSS por AGPS/rede, ou hardware USB externo |
| 3. NFC (S3NRN4V) | talvez (provável) | médio | Montar o nó `sec-nfc@27` com o `s3fwrn5` e ver se o NCI `CORE_RESET` responde por I2C |
| 4. Câmeras | não, a curto prazo | muito alto | Só o ISP do SoC é um beco sem saída. Prova possível: `i2cdetect`/chip-id de um sensor, sem imagem |
| 5. Modem (Shannon S5123, PCIe) | não, a curto prazo | muito alto | Nenhuma barata. Marco mínimo: subir o link PCIe 1 e enumerar o endpoint |
| 6. Digital (Goodix GW9558, ótico sob a tela) | não | muito alto | Ler o ID por SPI, no máximo. Autenticar depende de TEE e trustlet |
| 7. Hall / capa | sim | baixo | `gpio-keys` com `SW_LID` no GPIO `gpa3-6` e `evtest` |

## 1. Sensores

### Como funciona neste aparelho
- **Hub** **[código]**: `BCM4773@0` em SPI, compatible `ssp,BCM4773` (`rt.dts` ~linha 6265; devices.txt: `spi14.0 | ssp,BCM4773`). O controlador é o `spi@10650000`. O clock SPI é 25 MHz, modo CPOL+CPHA.
- **GPIOs do hub** **[código]**: `ssp-mcu-req` (`0x1ee` pino 5), `ssp-mcu-resp` (`0x1a3` pino 0), `ssp-host-req` (`0x197` pino 7), `ssp-batch-wake-irq` (`0x196` pino 5), `ssp-shub-int` (`0x19a` pino 0), `ssp-gps-pwr-en` (`0x23` pino 3). Supply: `vdd_mcu_1p8`. Existem também o PD `pd-ssp` e o nó `ssp` (`samsung,exynos-ssp`), que ficam ligados no dmesg ("pd-ssp - on").
- **Sensores atrás do hub** **[código]**: o DT descreve só o hub (posições do acelerômetro e do magnetômetro, tabelas de termistor, `ssp-mag-type`). Os chips reais (acelerômetro/giroscópio, magnetômetro, proximidade, luz frontal) não aparecem no DT. Quem os conhece é o firmware do MCU, e o host só vê tipos de sensor via `sensor_list.h` e os `factory/*.c`. O driver Samsung (`drivers/sensorhub/brcm`, ~19 mil linhas) fala um protocolo próprio SPI/BBD com o MCU. Detalhes: `ssp_spi.c`, `ssp_dev.c`, `ssp_firmware.c`.
- **Firmware do MCU** **[código]**: o patch do MCU fica **embutido no kernel**, não em `/vendor/firmware`. `drivers/sensorhub/brcm/bbdpl/bbd.c` inclui `r_os/bbd_patch_file_r8.h` (~800 KB, array C) e o expõe em `/dev/bbd_patch`. O daemon `lhd` (`/vendor/etc/sensor/lhd.conf`: `LhePatch=/dev/bbd_patch`, `LheBbdSensor=/dev/bbd_sensor`, `LheBbdControl=/dev/bbd_control`) é quem empurra o patch e fala com o MCU. Ou seja, o **carregador é o userspace Broadcom (`lhd`, binário proprietário) + o driver BBD**. Os blobs de patch são parte do repositório GPL do LineageOS, mas são firmware binário: **não os colocar em patches nem no git** (regra do projeto).
- **Sensores fora do hub** **[código]**:
  - `als_rear@29`, `ams,tcs3407` no `hsi2c@109D0000`. Tem IRQ em `0x198` pino 7 e GPIO de LED `0x35`. Supplies: `VDD_FLICKER_1P8` e `VDD_NFC_1P8`, esta última para o pull-up do I2C. O driver do vendor é "light_flicker" (`sensors.flicker.so` em `/vendor/lib64`). É o sensor de luz/flicker traseiro.
  - Grip `a96t3x6-i2c@20`, compatible `a96t3x6`, no mesmo I2C. IRQ em `0x199` pino 0, supply `VDD_GRIP_3P0`, firmware `a96t356_r8s.bin`. O blob está em `vendor/root/firmware/a96t356_r8s.bin`, e o driver Samsung (`a96t3x6.c`, em `sensorhub/brcm`) faz o firmup com o comando `0x3b`. É um MCU ABOV de touch capacitivo (as antenas de grip).
  - Os dois (e o NFC em 0x27) ficam no **mesmo barramento I2C**. Isso significa que o DT do mainline precisa do nó do hsi2c `0x109D0000` e dos supplies `VDD_NFC_1P8`/`VDD_GRIP_3P0`.

### O que existe no mainline / projetos públicos
- Nada para o hub SSP BCM4773 ou seu protocolo **[web, busca ampla sem resultado; só vi forks vendor, p. ex. Exynos5433 do e.foundation]**. Em gpsd-dev de 2019 sobre BCM4752 concluiu-se que o chip precisa de driver proprietário e comando de startup.
- No mainline do port existem `drivers/iio/light/tcs3472.c`, `tcs3414.c`, `as73211.c`, mas **não há `tcs3407`**. Eu não verifiquei se o `tcs3472` aceita o ID/registradores do `tcs3407` (a família TCS340x tem ALS por canais diferentes). **[proposta]**: tratar como driver novo, baseado na lógica em `drivers/` do Samsung.
- Não achei driver mainline para o `a96t356` (ABOV). **[código]**: o mainline tem `drivers/input/misc/` mas nada ABOV. Uma opção é adaptar `a96t3x6.c` como driver de input/IIO (proximidade).
- Não encontrei trabalho de Exynos 990 mainline para sensores **[web]**.

### Viabilidade e esforço
- Hub: **talvez**, mas só se alguém reimplementar o protocolo SSP em userspace (ou kernel) **e** aceitar redistribuir/carregar o patch do MCU. O MCU precisa do `bbd_patch` para rodar. Sem ele não há sensores. O protocolo é só visível em código Samsung 4.19 (GPL), então dá para portar o driver inteiro como módulo "ssp" mínimo. Esforço **alto** (algo como semanas) e sem garantia de que o mainline 6.12 ofereça os mesmos helpers. Um caminho mais curto é um daemon em userspace (como `lhd`) falando `spidev`, mas isso é igualmente grande.
- `tcs3407` e `a96t356`: **sim**, esforço baixo a médio. São chips I2C simples. O risco é o sequenciamento dos supplies (`VDD_NFC_1P8` serve a três dispositivos) e o fato de o MCU `a96t356` pedir firmware.
- Para o usuário final: o acelerômetro, giroscópio e magnetômetro (rotação de tela, bússola) e a proximidade (desligar a tela na ligação) **dependem do hub**. Sem ele o desktop continua usável. Para rotação, não há plano B de hardware.

### Primeira prova mínima
1. Declarar `hsi2c@109D0000` no DT e rodar `i2cdetect`: esperar 0x20 (grip), 0x27 (NFC), 0x29 (tcs3407). Só leitura.
2. Para o hub: ligar `vdd_mcu_1p8`, pulsar o reset e ler um `status` por `spidev` (CS em `0x30` pino 7). Só confirma o barramento SPI, não dá dados de sensor.

## 2. GPS

### Como funciona
**[código]**: o GNSS é o próprio BCM4773, o mesmo chip do hub (`ssp-gps-pwr-en` no DT do hub; `GpioNPowerPath=/sys/class/sec/gps/GPS_PWR_EN/value` em `lhd.conf`). O fluxo é: kernel Samsung (`bbdpl/bbd.c`, `bcm_gps_spi.c`, `bcm_gps_hostwake.c`) expõe `/dev/ttyBCM`, `/dev/bbd_*`. O daemon `lhd` e a HAL GNSS (`android.hardware.gnss@2.1`, `gps.xml` em `/vendor/etc/gnss/`) falam o protocolo Broadcom "RPC" (`bbd_rpc_lh.c`) com o chip. A pilha contém SUPL e A-GPS configurados em `gps.xml`. Os blobs são `lhd` e as libs de GNSS do vendor.

### Suporte livre
- Não encontrei nada: nem `gpsd` (que cobre NMEA/UBX/SiRF etc.) nem driver em `drivers/gnss/` (o mainline tem só `mtk`, `serial`, `sirf`, `ubx`, `usb` **[código, base do port]**) para BCM4773. Em 2022, a discussão LKML sobre BCM4751 mostra que o kernel não faz o driver de GPS Broadcom e que a decisão ficou para depois **[web]**.
- O firmware do GNSS é carregado pelo mesmo mecanismo do hub, ou seja, depende do blob.

### Viabilidade
**Não**: não há caminho livre conhecido. Um driver exigiria reimplementar o protocolo Broadcom (RPC/BBD, patch) a partir do código GPL do kernel e de binários proprietários (`lhd`). Opção honesta: usar GNSS externo (USB), ou deixar o GPS para uma rota Halium/Android (`gps.xml` e `lhd` rodando em uma base Android). Isso se cruza com o item 1: se resolvermos o hub/BBD, o GPS passa a ser o mesmo canal.

### Primeira prova
Nenhuma barata. Se o canal SPI do item 1 funcionar, o próximo passo é ver se o BCM4773 manda NMEA bruto por `/dev/ttyBCM` depois do patch. **[proposta, sem evidência]**.

## 3. NFC

### Como funciona
**[código]**: `sec-nfc@27` no hsi2c `0x109D0000`, compatible `sec-nfc`: `ven-gpio` (`0x23` pino 0), `irq-gpio` (`0x197` pino 2), `firm-gpio` (`0x30` pino 0), `clk_req-gpio` (`0x198` pino 6, função `0x0f`), supply `VDD_NFC_1P8` e **clock `oscclk_nfc` do AP** (`sec-nfc,nfc_ap_clk`, `ldo_control`). dmesg Samsung: `[sec_nfc] parse_dt() irq : 10, ven : 140, firm : 114`, `probe() success`. O driver Samsung (`drivers/nfc/sec_nfc.c`) é só um **dispositivo de caracteres**: ioctls de modo (power off/on/firmware), leitura/escrita crua em I2C. O NCI e o firmware ficam no **userspace** (libnfc-nci da Samsung, `libnfc-sec-vendor.conf`: `FW_FILE_NAME="sec_s3nrn4v_firmware.bin"`, `RF_HW_FILE_NAME`/`RF_SW_FILE_NAME` = `sec_s3nrn4v_hwreg.bin`/`swreg.bin`, `FW_CFG_CLK_SPEED=0x12`, `FW_UPDATE_MODE=0`). Os três blobs estão em `vendor/root/firmware/nfc/` (184 KB) e `vendor/root/etc/nfc/`. Há também `ese_p3` (eSE, `spi10.0`) e `k250a`, não considerados aqui.

### O que existe
- Mainline `drivers/nfc/s3fwrn5` (core, I2C, UART, firmware) existe na base. Compatible I2C: `samsung,s3fwrn5-i2c` **[código]**. Cobre S3FWRN5 e S3FWRN82. O firmware é carregado pelo driver (`firmware.c`, comandos GET_BOOTINFO/ENTER_UPDATE_MODE/UPDATE_SECTOR).
- **Série net-next de 3 jul 2026 "nfc: s3fwrn5: support the S3NRN4V variant"** (Jorijn van der Graaf) **[web]**, [lkml](https://lkml.rescloud.iu.edu/2607.0/07461.html). Pontos: o S3NRN4V vem com firmware funcionando e **o driver pula o download de firmware** (protocolo de bootloader não implementado). Carrega os registradores de RF com outro comando proprietário (`DUAL_OPTION`). Usa um **CLK_REQ** que o driver precisa atender (nova propriedade `clk-req-gpios`) para o chip gerar a portadora de 13,56 MHz. Testado em um Fairphone 6 com mainline (modo leitor, tags ISO 14443-4). **Status: série enviada, não vi se foi aceita.** Isso corresponde ao nosso DT (`clk_req-gpio`, `nfc_ap_clk`). Eu li só o resumo; **não li os patches nem confirmei o compatible/binding**.
- Diferença para nós: o nosso clock vem do AP (`oscclk_nfc`, clock `0x384`), então o driver mainline (que espera um GPIO/clock simples) precisa também habilitar esse clock do Exynos. Não verifiquei se o CMU do mainline do port expõe `oscclk_nfc`.

### Comparação com o Samsung `sec_nfc.c`
Mesmos 3 GPIOs (ven, irq, firm) que o mainline chama `en`, `irq` e `fw_en`/`wake`. Em modo normal o mainline faz o mesmo NCI por I2C. O que o Samsung faz de diferente (userspace) é carregar `swreg`/`hwreg`: isso é o que a série do S3NRN4V implementa no kernel.

### Viabilidade e esforço
**Talvez, e provável**, esforço **médio**: aplicar a série do S3NRN4V (ou cherry-pick) sobre o `s3fwrn5` do port, escrever o nó DT, habilitar o clock do AP, e portar o `swreg/hwreg` (blob proprietário, carregar do rootfs, nunca no git). Risco: a série pode assumir outro mecanismo de clock; o `sec_s3nrn4v_hwreg.bin` pode ser aplicado de forma diferente. Para o usuário, NFC útil só com `neard`/`libnfc` e leitores simples. Pagamento (Samsung Pay/eSE) fora de escopo.

### Primeira prova
Habilitar `CONFIG_NFC_S3FWRN5_I2C`, nó no hsi2c `0x109D0000` endereço `0x27` com `en`/`irq`/`fw` e clock, ver `nfcpy`/`neard` sem erro de `CORE_RESET_CMD`. Isso é seguro (só I2C e GPIO), mas liga um regulador e um clock: tentar depois de `i2cdetect`.

## 4. Câmeras

### Como funciona
**[código]**: sensores no DT: `is-hi847@21` (id 2), `is-imx616@1A`, `is-2ld@10` (S5K2LD, e `is_sensor_2ld@20` no segundo bloco), `is-3l6@2D` (S5K3L6), mais OIS (`172f0000.ois_mcu`), flash `rt8547` e PDP. dmesg: `is_vender_dt ... front2_sensor_id read is fail`, reservas ION (`camera`, `secure_camera`, `camera_rmem`). O pipeline é o **Exynos IS (FIMC-IS)**: o ISP/IPP/MCSC roda **firmware próprio** no SoC. As `setfile_*.bin` em `vendor/root/firmware` são ajustes (tuning) para esse firmware. O userspace é `libexynoscamera3.so` (HAL, proprietária).

### O que existe
- Mainline: nenhum driver de ISP/CSIS do Exynos 990 (o `exynos4-is` só serve para SoCs antigos, como o enunciado já apontava). Sem driver de CSIS, sem os blocos DNS/IPP/MCSC/TNR.
- Sensores no mainline do port **[código]**: há `hi846.c` e `hi847.c`; este último é um driver da Intel (copyright "Intel Corporation", inclui `linux/acpi.h`, feito para IPU/ACPI), não testado em DT por nós. **Não há** `imx616`, `s5k3l6` nem `s5k2ld`. Para o S5K3L6, há um RFC de jun/2026 no linux-media (driver reescrito a partir do Librem 5) **[web, não li o patch]**. Para IMX616/S5K2LD não achei nada **[web]**.
- libcamera sabe lidar com qualquer sensor com driver V4L2 mainline (`camera_sensor_properties.cpp`), mas **só quando há ISP/pipeline mainline**. Para o Exynos 990 não há.
- Ubuntu Touch r8s (Android 13, Halium) tem câmera instável segundo o fórum UBports **[web]**; Halium usa a HAL Samsung inteira.

### Viabilidade
**Não** a curto prazo (esforço **muito alto**): seria preciso um driver de CSIS + pipeline de ISP com firmware Samsung. Um caminho parcial seria expor o sensor em modo raw (CSIS-2 + DMA) sem ISP, o que exige escrever a parte do SoC do zero. **[proposta, sem prova]**.

### Primeira prova
Ler o chip-id de um sensor por I2C (com regulador e clock ligados). Isso confirma energia/endereço e não dá imagem.

## 5. Modem (chamadas e dados)

### Como funciona
**[código]**: o modem é um **Shannon S5123** em **PCIe canal 1** (`mif: create_modemctl_device: s5123`, `LINK:PCIE`, `pci_ch_num = 1`, `pci_db_addr = 0x14d60000`, `mif,ipc_version = 0x32`, 22 dispositivos de I/O). O driver é o `cpif` (`CPIF-20210901R1`), com os GPIOs `ap2cp_cp_pwr_on`, `ap2cp_nreset_n`, `cp2ap_cp_ps_hold`, `ap2cp_wake_up`, `cp2ap_phone_active` e mais. A memória é compartilhada (`cp_shmem`, `cp_rmem`, `cp_msi_rmem` reservadas no dmesg). O boot do modem passa por **SPI 16** (`cpboot_spi_probe: bus_num:16`) com o daemon `cbd` (do vendor) carregando firmware do modem (que vive em partições Samsung, não em `/vendor/firmware`; **não procurei em `partitions.txt`**). A camada de rádio é a RIL Samsung (`libril_sem.so`, `libsec-ril`, `sehradiomanager.conf`).

### O que existe
- Projetos livres para Samsung IPC (Replicant `libsamsung-ipc`, `samsung-ipc`) cobrem modems **antigos** (XMM6262, Galaxy S3, HSIC, protocolo "SIPC/FMT-RFS") **[web, Replicant redmine]**. Shannon S5123 usa outro protocolo (IPC v0x32, `link_type` PCIe, `modem_type` 1). **Não encontrei nenhum trabalho livre para modems Shannon/Exynos modernos**, nem no mainline nem no postmarketOS. Um item do Replicant lista modems LTE em mainline como acompanhamento aberto, sem resultado **[web]**.
- O mainline tem PCI do Exynos (`pci-exynos.c`) e o port já declara um controlador PCIe 0 (Wi-Fi QCA6390) **[código, `exynos990-r8s.dts` ~linha 610]**. O canal 1 (modem) não está no DT do port.

### Viabilidade
**Não** a curto prazo, esforço **muito alto**: seria preciso (a) subir o PCIe canal 1 com o nó DT correto, (b) reescrever o `cpif`/`cbd` (carregar firmware via SPI e atender o protocolo shmem do CP) e (c) uma pilha de RIL aberta para IPC v0x32 (`ofono`/`ModemManager` não conhecem o protocolo). O firmware do modem é proprietário. A rota Halium/Android é a única com modem hoje (e ainda assim o relato do UBports não confirma o modem no r8s).

### Primeira prova
Marco só de hardware: subir o PCIe canal 1 e enumerar o dispositivo (vendor/device ID do Shannon, depois que `cp_pwr_on`/`nreset` forem acionados). Cuidado: acionar o GPIO do modem sem a pilha pode ser inócuo, mas aqui não há evidência. Tratar como tarefa de pesquisa, não de entrega.

## 6. Leitor de digital

### Como funciona
**[código]**: **Goodix GW9558** (`goodix,gw9558x`, `goodix,chip_id = "GW9558"`, `goodix,modelinfo = "G780"`, supply `VDD_BTP_3P3`, reset em `0x197` pino 3). Barramento SPI (`spi4.0 | goodix,gw9558x_factory`; clock SPI 25 MHz). O touchscreen Zinitix expõe a área FOD (`get_fod_info: top:155, edge:66, bottom:132`, `fod_with_finger_packet: 1`), o que indica sensor **ótico sob a tela** (o touch e o display dão a região e o brilho). **Não é ultrassônico** (esse é o S20/Note 20 Qualcomm); a ausência de provedor Qualcomm no DT confirma.
- O driver do kernel (`drivers/fingerprint/gw9558x_*.c`, `fingerprint_sysfs.c`) é só um **transporte** (SPI, GPIO, clocks `fp-spi-pclk`/`fp-spi-sclk`, controle de energia). Sob `CONFIG_TZDEV_BOOST`/`ENABLE_SENSORS_FPRINT_SECURE`/TEEGRIS o SPI é "securizado" para o trustlet no **TEE Samsung**. O vendor tem `android.hardware.biometrics.fingerprint-V4-ndk.so`, `libqfp_sensortest.so`, `libegis_fp_normal_sensor_test.so`. Reconhecimento, templates e captura passam pelo trustlet.

### O que existe
Nenhum driver livre para a família GW95xx **[web: libfprint e goodix-fp-linux-dev cobrem chips Goodix USB de laptop, não achei GW9558]**. Mesmo se lêssemos a imagem bruta por SPI, não há algoritmo de captura (exposição, calibração do pixel, o display deve iluminar o dedo) nem matching abertos. A calibração (`goodix,rb`, `position`) vive no blob.

### Viabilidade
**Não** (esforço muito alto, pesquisa de engenharia reversa). Na rota Halium/Android o leitor funciona por TEE; na rota nativa, não há TEE Samsung acessível. **[proposta]**: tratar como fora de escopo; usar senha/chave FIDO2 externa.

### Primeira prova
Ler o chip-id por SPI após o reset (só prova o barramento). Autenticação: sem caminho.

## 7. Sensor de capa (hall)

### Como funciona
**[código]**: dois nós no DT:
- `hall` (`compatible = "hall"`): `hall,gpio_flip_cover = <0x199 0x06 0x01>`, ou seja, **gpa3 pino 6**, `pinctrl hall-irq` (`gpa3-6`, função 0xf = interrupção externa), flag 1 (ativo em baixo). O driver Samsung `drivers/input/misc/hall/hall.c` registra `ddata->event_val = SW_LID` e reporta `input_report_switch`, com leitura dupla do GPIO para filtrar ruído (`first`/`second`).
- `certify_hall` (`compatible = "certify_hall"`): `certify_hall,gpio_certify_cover = <0x196 0x02 0x01>`, ou seja, **gpa0 pino 2**, `pinctrl certify-hall-irq` (`gpa0-2`). Driver `certify_hall.c`: `event_val = SW_MACHINE_COVER` (código Samsung fora do mainline) e lógica invertida (`!gpio_get_value`). É o sensor do Clear View cover / certificação de acessório.

### Como fazer
**[proposta]**: no DT do board, nó `gpio-keys` padrão do mainline, sem driver novo:

```dts
gpio-keys {
	compatible = "gpio-keys";
	pinctrl-names = "default";
	pinctrl-0 = <&hall_irq>;   /* a ser criado no pinctrl do r8s: gpa3-6, função EINT */
	cover {
		label = "cover";
		gpios = <&gpa3 6 GPIO_ACTIVE_LOW>;   /* flag 1 no DT real */
		linux,input-type = <EV_SW>;
		linux,code = <SW_LID>;
		wakeup-source;
		debounce-interval = <50>;
	};
};
```

- O nó do certify (`gpa0-2`) pode virar um segundo botão com `linux,code = <SW_MACHINE_COVER>` (código 0x10, existe em `linux/input-event-codes.h` do mainline; verificar). Pode ser ignorado.
- Confirmar polaridade no aparelho com `gpioget` antes de apostar no sentido (aberto/fechado). A flag 1 é da DT Samsung: `hall.c` não inverte (lê `gpio_get_value` direto), então o tratamento exato precisa ser medido.
- Observação: o `gpa3-6`/`gpa0-2` são pinos de wakeup externo. O `wakeup-source` faz o `SW_LID` poder acordar o aparelho. `systemd-logind` usa `SW_LID` para suspender, o que é perigoso num celular sem suspender confiável: ligar `HandleLidSwitch=ignore`.

### Viabilidade e esforço
**Sim**, esforço **baixo** (um nó DT, sem driver novo). Pré-requisito: o pinctrl do port deve expor `gpa3`/`gpa0` e o `exynos-pinctrl` com EINT (já usado por outros botões do port; não verifiquei).

### Primeira prova
`gpiomon`/`gpioget` na linha de `gpa3-6` com a capa aproximada de um ímã, depois `evtest` com o nó `gpio-keys`.

## Ordem sugerida
1. Hall (item 7): rápido, sem risco. 2. I2C `0x109D0000` (itens 1b e 3). 3. NFC (item 3), se a série S3NRN4V for aceita. 4. Hub/BBD (item 1a e 2) como projeto separado. Itens 4, 5 e 6 só se o escopo mudar para Halium/Android.

## O que não verifiquei
- Os patches da série S3NRN4V e do RFC do S5K3L6 (li só resumos de terceiros). Não confirmei se foram aceitos.
- Os chips reais atrás do hub SSP (precisaria ler `ssp_dev.c`/`factory/*` com a configuração do r8s) e o conteúdo do blob `bbd_patch_file_r8.h`.
- Onde o firmware do modem (`cbd`) fica nas partições; o pinctrl/EINT do port; a wiki do pmOS do r8s.

## Fontes
- Série NFC S3NRN4V: https://lkml.rescloud.iu.edu/2607.0/07461.html
- s3fwrn82 / s3fwrn5 no mainline: https://lore.kernel.org/linux-devicetree/CAEx-X7cufBcO38RR2SQzvTOA=JRyG7XSR-KNMcui99WGrsvfZw@mail.gmail.com/T/
- pmOS r8s: https://wiki.postmarketos.org/wiki/Samsung_Galaxy_S20_FE_(samsung-r8s) (não lido)
- Patches Exynos 990 (hubble): https://patchwork.kernel.org/series/915816/mbox
- Discussão BCM4751 GNSS: https://lkml.iu.edu/2204.2/09646.html
- gpsd-dev BCM4752: https://lists.gnu.org/archive/html/gpsd-dev/2019-09/msg00029.html
- Replicant (modems Samsung antigos): https://redmine.replicant.us/projects/replicant/wiki/XMMUpstreaming
- UBports S20 FE: https://forums.ubports.com/topic/10440/samsung-s20-fe-ut-ubuntu-touch-android-13/19
- Camera sensors libcamera: https://docs.libcamera.org/master/sensor-support.html
