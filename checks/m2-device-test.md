# M2 físico — evidência parcial, 17/11/2026

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

## Estado após reinício

Executado `adb reboot`. O telefone ainda não reapareceu em ADB/fastboot no trecho observado; solicitada ao proprietário a identificação da tela. Não inferir causa ou sucesso do loader pela ausência de USB. A consulta `fastboot getvar product` ficou aguardando dispositivo (com timeout de 35 segundos).

Não houve `fastboot boot` de mini/slim, gravação de kernel no slot virtual, gravação de userdata nem instalação do Arch/Omarchy no aparelho. M2 não está aprovado. Boot agora contém lk3rd e slot virtual vazio; não presumir retorno normal ao LineageOS sem restaurar seu boot ou completar o caminho planejado. Recovery preservado em disco e firmware Samsung/backup externo disponíveis; retorno ainda não ensaiado após essa escrita.
