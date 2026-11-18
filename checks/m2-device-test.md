# M2 físico — lk3rd e dois boots em RAM, 17/11/2026

Proprietário solicitou prosseguir com o aparelho conectado ("se não, pode fazer") e confirmou ausência de dados pessoais. Cópia externa concluída e verificada: [m0-external-backup.md](m0-external-backup.md).

## Observado antes da escrita

- Android inicialmente acessível, `uid=2000`; reinício para Recovery pelo ADB. Após autorização, Recovery com `uid=0`, `SM-G780F/r8s`, verified boot `orange`, bateria 100%.
- Boot/recovery/userdata resolvidos no aparelho como `sda13`/`sda14`/`sda32`.
- Boot atual tinha SHA-256 `5a5bd79383d9c3836e5353da4546111a1c61e1e20d3cf3f9143d98160d4d0f7a`, igual ao backup `stock-boot.img` (imagem anterior do aparelho, não o firmware Samsung baixado).
- Recovery e DTBO também iguais aos backups anteriores.
- `flash-boot.sh` em dry-run aprovou alvo, tamanho, bateria e backup. Log sanitizado: `logs/m2-lk3rd-dry-run.log`.

## Escrita realizada

Com root já disponível no Recovery, usado o caminho ADB documentado pelo port, sem necessidade de gravar pelo Heimdall. `/data` estava desmontado e `/data/local/tmp` ausente. Para staging em RAM, criado `/data/local/tmp` como symlink para `/tmp` (tmpfs do Recovery); userdata não foi montado.

`packaging/host-tools/flash-boot.sh out/boot/lk3rd-r8s.img --write` concluiu: imagem de 2.097.152 bytes, SHA-256 `48a15319a0ee3dcb65faaacaf51bd4bb897925c5efc03d19543eaa4afc4286ab`. O script zera a partição boot e grava o lk3rd; o restante, que vira o slot virtual do loader, ficou vazio. Verificação de upload antes da escrita e readback dos primeiros 2 MiB aprovaram. Log: `logs/m2-lk3rd-write.log` (identificador USB omitido).

Após a escrita, hashes de recovery e DTBO permaneceram iguais:

- Recovery: `7979e57224da6d4466b8ed3fd1e94051787daf87044979ea7866eecb953e14d4`.
- DTBO: `82b59eba3f952bfbc73d9b866105e878783ef40ca5a89bd93b08bdea01c7bd0c`.

## lk3rd e fastboot comprovados

Após o primeiro reinício, o proprietário relatou a tela `lk3rd_Fastboot Mode`, produto r8s. O host então detectou USB `18d1:4d00`, produto `r8s - lk3rd`. `fastboot getvar product` confirmou `r8s - lk3rd`.

## Mini em RAM

- `fastboot boot out/boot/r8s-mini.img`: envio e boot `OKAY` (24.672.256 bytes, hash do baseline conferido antes do envio).
- USB enumerou como `r8s mainline ALIVE`, dispositivo serial `/dev/ttyACM0` e Ethernet USB.
- Console executou `uname -a`: Linux `6.12.0-rc5-next-20241104-r8s`, AArch64. `MemTotal: 5851100 kB`.
- `/proc/mounts` mostrou apenas rootfs em RAM e pseudo-filesystems; nenhuma partição UFS montada.
- `reboot -f` retornou ao fastboot do lk3rd, confirmado pelo host.
- Logs: `logs/m2-mini-boot.log`, `logs/m2-mini-console.log`, `logs/m2-mini-return-fastboot.log`.

## Slim em RAM

- `fastboot boot out/boot/r8s-ram.img`: envio e boot `OKAY` (63.150.080 bytes, hash do baseline conferido).
- Console Debian 13 `r8s-slim` com root; mesmo kernel AArch64. `systemctl is-system-running` = `running`, `systemctl --failed` = 0 unidades.
- Nenhuma partição UFS montada; sistema permaneceu em RAM.
- Touchscreen Zinitix registrado em `/dev/input/event0`; botões em `event1`. Sem teste de eventos reais por toque.
- `/dev/dri/card0`, `card1`, `renderD128` presentes. Panfrost identificou Mali-G77 e inicializou DRM. Não foi executado compositor nem renderer de hardware.
- UFS foi enumerado e lido, sem escrita de rootfs. Há avisos `dme-set` durante inicialização: o ensaio de leitura não valida escrita ou integridade de carga prolongada.
- Logs: `logs/m2-slim-boot.log`, `logs/m2-slim-console.log`, `logs/m2-slim-kernel-warnings.log`, `logs/m2-slim-ufs-read.log`.

## Novo mapa após inicializar lk3rd

O lk3rd **altera a GPT persistentemente** no primeiro boot para separar sua região da imagem de kernel. Observado no Linux nativo:

| Partição | Início (setores de 512 bytes) | Tamanho |
| --- | ---: | ---: |
| `sda13`, label `lk3rd` | 248960 | 2 MiB |
| `sda33`, label `boot` | 253056 | 57 MiB |
| `sda14`, label `recovery` | 369792 | 65,8 MiB |
| `sda32`, label `userdata` | 22802432 | 108,3 GiB |

Evidência: `logs/m2-native-partition-map.log`; implementação em `sources/lk3rd/lib/lk3rd/automatic_repartitioning.c` (`add_lk3rd_part`, fonte fixada no manifesto). A referência antiga `boot → sda13/59 MiB` descreve o estado **anterior** e não deve ser usada para nova gravação/restauração sem conferir o mapa atual. O loader também escreve opções na sua região de armazenamento persistente, offset `0x175000` (`persistent_storage.c`); os bytes desse trecho diferem dos do arquivo original após inicializar. O hash nativo da região de 2 MiB foi `2b78921651a47e1f3f190df07ffc3c544323e0083d57cc1abb54a4effac8082a`, enquanto o readback imediatamente após o flash havia aprovado o hash do artefato. Não confundir a região `lk3rd` com a nova `boot`.

## Pendências e estado final

Bluetooth apresentou timeouts HCI `-110` e falha ao ler versão QCA. Também há avisos de CPU features/MPIDR, reguladores dummy e ausência de `regulatory.db`/`autofs4`. Não declarar estabilidade ou todos os drivers funcionais por `systemd=running`.

## UFS e clocks, leitura de novo no slim

Segunda sessão no mesmo slim, ainda em RAM, sem flash e sem montar UFS. O aparelho já estava no console `root@r8s-slim` com o carimbo `Tue Nov 17 15:41:42 UTC 2026`. `/proc/mounts` sem `sd`/`ufs`.

Os quatro `dme-set` (`0x9540`/`0x321`) ocorrem e, na linha seguinte, o link vai a `FAST series_B G_3 L_2`. Sysfs: `HS_GEAR3`, 2 pistas, `HS_RATE_B`, `ACTIVE`. Leitura de `/dev/sda` (512 B), `/dev/sda13` (2 MiB, hash igual ao da sessão anterior) e `/dev/sda33` (4 KiB zero). `eol_info=0x01` e estimativa de vida `0x0B` nos dois campos; a leitura funcionou. Análise e origem no código: [ufs-clocks.md](../research/ufs-clocks.md). Logs: `logs/m2-ufs-dmesg.log`, `logs/m2-ufs-sysfs.log`.

**Saúde 0x0B (17/11/2026, boot novo em RAM + releitura `logs/m2-ufs-health.log`):** `0x01/0x0B/0x0B` estável; sysfs lê offsets 2/3/4 sem cache (JEDEC confere), então descartados bug de decode e descritor errado. Vida `0x0B` = ciclos P/E excedidos (vendor-specific) — nenhum patch de kernel corrige. Resolução = mitigação (RAM-first, sem escrita pesada) + confirmação no Recovery/Android antes de instalação persistente; ver `research/ufs-clocks.md`.

`clk: Not disabling unused clocks` é o `clk_ignore_unused` da cmdline. `exynos990-cmu 18c00000` não liga porque `&pd_aud` está `disabled`; o driver ficou só com `10a00000`. `exynos-clkout` continua `-22`. Logs: `logs/m2-clocks-dmesg.log`, `logs/m2-clocks-sysfs.log`. Isso não testa escrita nem carga longa do UFS.

A coleta anterior no mesmo slim (`logs/m2-ufs-read.log`) hasheou 1 MiB de `sda33` (`30e14955…`), que é 1 MiB de zeros; os 4 KiB desta sessão são o prefixo desse bloco. A máscara de sync não foi aplicada. Escrita, mount e power-mode continuam sem ensaio. Seis leituras de recovery/DTBO, noutra coleta: [ufs-clocks-codex.md](../research/ufs-clocks-codex.md).

Solicitado `systemctl reboot` ao final do slim para voltar ao lk3rd. O resultado do retorno está em `logs/m2-slim-return-fastboot.log`. Não houve gravação de kernel no slot virtual, gravação de userdata nem instalação do Arch/Omarchy no aparelho. O slot boot permanece vazio; retorno normal ao LineageOS exige procedimento de restauração compatível com o mapa alterado. Recovery permaneceu preservado; a restauração completa ainda não foi ensaiada.

V2 (console real em RAM, sem UFS montado) foi demonstrado com mini e slim. M2 completo permanece pendente: Arch mínimo, cinco boots, rede/toque reais, energia/temperatura e recuperação comprovada.
