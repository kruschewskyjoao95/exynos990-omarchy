# Carregamento lento no r8s (19/11/2026)

Relato do proprietário: no notebook (porta que devia dar 10 W), com dois cabos, a carga ficou em 1,7 a 2,5 W; num carregador de notebook de 45 W, ficou em 6 W. Observado no aparelho, kernel #18, sem flash.

## O que o aparelho informa (observado)

- Não há `/sys/class/typec`. O driver `max77705-typec-r8s` (`out/work/linux/drivers/usb/typec/max77705_r8s_typec.c`) só acompanha o firmware da PMIC: lê o estado de CC e PD, move o papel USB e liga o VBUS em modo host. **Não negocia USB Power Delivery.** `psrdy` fica 0 em todos os eventos e a tensão fica em 5 V.
- Na porta testada, `/sys/kernel/debug/max77705-typec/state` mostra `cc_status0 = 0x91` (ISTAT = 1, a fonte anuncia só corrente padrão de USB, 0,5 a 0,9 A) e `bc_status = 0x81` (tipo de carregador 1). O `rp=0` do log do driver não reflete esse campo.
- O limite de entrada era fixo em 1,525 A com carga de 1,5 A (`r8s-charge-limit.sh`), com a carta de que o AICL recua numa fonte fraca. Em 5 V isso é no máximo 7,5 W, o que explica os ~6 W do carregador de 45 W.
- Com o cabo ligado, a bateria **descarregava**: -537 mA com o modem ligado e -320 mA com ele desligado (brilho 30%). O celular consome mais do que a porta fornece. Por isso a carga líquida some.

## Mudança feita

`packaging/power/r8s-charge-limit.sh`: lê o anúncio da fonte (ISTAT). Com 3 A, entrada de 3,0 A e carga de 2,0 A; nos demais casos, 1,5 A como antes. Registra `ISTAT` e `chgtyp` em `journalctl -t r8s-charge`. Instalado no aparelho (cópia do original em `r8s-charge-limit.sh.bak`). A fonte de 3 A **não foi testada**: não havia o carregador de 45 W ligado.

`packaging/build-env/build-arch-rootfs.sh` ainda instala a versão antiga de `sources/port/device/`.

## O que falta

- **Negociar PD (9 V).** O Android fecha contrato PD e carrega a ~25 W. Aqui, a seleção do PDO é feita pelo AP: o firmware da PMIC recebe as capacidades da fonte e o driver precisa escolher um PDO e enviar o comando. Isso é trabalho de kernel (driver + teste com carregador PD e medidor USB) e não existe hoje.
- Na porta do notebook (corrente padrão), mesmo com PD o ganho depende de a porta oferecer PD.
