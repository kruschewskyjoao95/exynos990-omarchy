# USB 3 no r8s (19/11/2026)

Pedido do proprietário: habilitar USB 3 (celular USB-C para notebook USB-A 3.0). Motivo: a carga pela porta fica em ~2,2 W porque o aparelho negocia USB 2.0 e declara 500 mA (`checks/charging-r8s.md`).

## Estado atual (observado no aparelho, kernel #18)

- `usbdrd_dwc3` (`out/work/linux/arch/arm64/boot/dts/exynos/exynos990-r8s.dts`): `maximum-speed = "high-speed"`, só `phy-names = "usb2-phy"`. `/sys/class/udc/*/maximum_speed` e `current_speed` = `high-speed`. O gadget (`/sys/kernel/config/usb_gadget/r8s/max_speed`) aceita `super-speed-plus`.
- O kernel tem `phy-exynos5-usbdrd.c` com o init UTMI do 990 (`exynos990_tunes_utmi_postinit`), sem SuperSpeed. O USB é o canal de recuperação do projeto (ACM + RNDIS), então o HS deve continuar funcionando sempre.
- Boot: `lk3rd` em sda13, kernel na partição `boot` (sda33). Teste sem gravar: `fastboot boot` (RAM), como em `checks/m2-device-test.md`.

## O que o kernel da Samsung usa para SuperSpeed (código, `sources/lineage-kernel-universal9830`)

- DT (`exynos9830-universal9830_common.dtsi`): `maximum-speed = "super-speed-plus"`, `snps,quirk-frame-length-adjustment = <0x20>`, `snps,ux_exit_in_px_quirk`, `snps,elastic_buf_mode_quirk`, `usb3-lpm-capable`, `snps,dis-u2-freeclk-exists-quirk`; nó `usbdrd_phy0` com `phy,gpio_phy_port = <&gpm26 0 0>`, `hs_tune_param` e `ss_tune_param`.
- PHY: `drivers/phy/samsung/phy-exynos-usbdrd.c` (2425 linhas) chama a CAL `phy_exynos_usb_v3p1_*` (`phy-exynos-usb3p1.c`, `phy-samsung-usb3-cal.c`, 1207 linhas) e o PHY combinado USB/DP `phy_exynos_usbdp_g2_v2_*` (`phy-exynos-usbdp-gen2-v2.c`, 4428 linhas, mais ~19,5 mil linhas de tabelas de registradores). Sequência de ligar: `pma_ready` → `usbdp_g2_v2_enable` → `usb_v3p1_enable` → `pipe_ovrd`; depois `tune`.
- Glue do controlador: `drivers/usb/dwc3/dwc3-exynos.c` (795 linhas).
- A orientação do cabo (CC1/CC2) precisa chegar ao PHY. O driver `max77705-typec-r8s` já lê o pino (`cc_status0`, campo PINSTAT), mas não repassa a ninguém.

## Plano por etapas

1. **Registradores e sequência mínima** (só leitura do código): extrair do `usbdp_g2_v2` apenas o caminho USB3 (sem DisplayPort e sem EOM), com a tabela de registradores usada por ele. Meta: decidir se dá para portar só isso.
2. **Port do PHY SuperSpeed** para `phy-exynos5-usbdrd.c` (ou um driver novo `phy-exynos990-usb3.c`), atrás de `CONFIG_`/overlay, mantendo o HS como padrão.
3. **DT**: `usb3-phy` no `usbdrd_dwc3`, `maximum-speed = "super-speed"`, quirks do vendor, e a orientação via `typec_mux`/gpio.
4. **Teste em RAM**: `fastboot boot` com Wi-Fi/ssh como canal de controle (o USB pode cair). Critério: `current_speed = super-speed` com o notebook; depois a corrente de entrada.
5. Só depois de passar: gravar na partição `boot`, com backup da atual.

## Levantamento da etapa 1 (19/11/2026, observado)

- **DT da Samsung para o PHY** (`exynos9830.dts`): quatro regiões de registradores: `0x10C00000` (0x200, controle USBCON: `COMBO_PMA_CTRL`, `LINK_CTRL`), `0x10AE0000` (0x2800, PHY combinado USB/DP) e `0x10AF0000` (0x800, PCS do combo), mais `0x10E00000` (o próprio controlador). `phy_version = 0x301`, `sub_phy_version = 0x400`, `pmu_offset = 0x72c`, `pmu_offset_dp = 0x704`, `phyclk_mux = "none"`, ref `ext_xtal`. O DT do r8s mapeia só `0x10C00000 0x50000`.
- **Sequência SuperSpeed (`exynos_usbdrd_pipe3_init`)**: lê o gpio de orientação (`phy,gpio_phy_port`, gpm26-0, inverte se `reverse_phy_port`), grava `used_phy_port`, `phy_exynos_usb_v3p1_g2_pma_ready()`, `phy_exynos_usbdp_g2_v2_enable()`. O HS é um caminho separado (`utmi_init`: `usb_v3p1_enable` e `pipe_ovrd`), que o kernel atual já faz com código próprio.
- **Arquivos a trazer**: `phy-exynos-usbdp-gen2-v2.{c,h}`, `-reg.h` (17,7 mil linhas), `-reg-pcs.h`, `phy-exynos-usb3p1.{c,h}`, `phy-exynos-usb3p1-reg.h`, `phy-samsung-usb-cal.h`. EOM e BIST do `usbdp` não são necessários. `sources/` não vai para o git: o código entra como patch da série (GPL-2.0, mesma licença do kernel).
- **Kernel em execução**: sem `OF_OVERLAY`/`OF_CONFIGFS`, então mudar o DT exige um kernel novo (nada de teste a quente). PHY e dwc3 são built-in.
- **Compilação**: `build-m1-kernel.sh` apaga e refaz `out/work/linux` e grava em `out/boot/`. A tarefa de áudio (`0144`) usa a mesma árvore; compilar o USB 3 ali desfaria o trabalho dela. Precisa de coordenação ou de um diretório de trabalho separado no script.

## Implementação (19/11/2026)

- `packaging/kernel-patches/0145-r8s-usb3-superspeed-phy.patch` (na série): código do PHY combinado USB/DP da Samsung (`phy-exynos-usbdp-gen2-v2*`, `phy-exynos-usb3p1-reg.h`, `phy-samsung-usb-cal.h`), `phy-exynos990-usb3.c` (cola: `pipe_ovrd`, `pma_ready`, ativação do combo; calibração padrão), e as mudanças em `phy-exynos5-usbdrd.c`: instância PIPE3 do 990, `exit` do PIPE3 sem desligar o PHY HS, `set_mode` ignora o SuperSpeed. **Inerte sem as regiões do DT**; o `init` nunca falha (sem trava de SuperSpeed o porto continua USB 2.0). Opção `CONFIG_PHY_EXYNOS990_USB3` (ligada por `build-m1-kernel.sh` na série).
- `0146-r8s-usb3-enable-dwc3-superspeed.patch` (**fora da série**): `usb3-phy` no dwc3, regiões `0x10ae0000` e `0x10af0000` e GPIO de orientação `gpm26-0` no nó do PHY, `maximum-speed = "super-speed"`. Entra só por `R8S_EXTRA_PATCHES` para teste em RAM.
- A calibração do combo depende da revisão do chip (`exynos_soc_info.main_rev/sub_rev`): o aparelho é **EVT1.1** (`/sys/devices/soc0/revision = 11`), fixado no código, com aviso no log para outra revisão.
- Compilação: `R8S_OUT_DIR` (saída separada, sem tocar em `out/work/linux` do áudio), `R8S_SKIP_PATCHES` (camera `0123 0124 0127 0128 0129 0131` não aplicam numa árvore nova) e `R8S_EXTRA_PATCHES`. Base: kernel completo da série; depois `Image` e DTB incrementais com `0145` e `0146`. Imagem: `out/usb3/boot/r8s-ufs.img` (24.532.992 B, SHA-256 `49d3205a5b405eea491116ac789c9688d4cfddd6b6f8fffee569d0ebefbcb5b2`), ainda **não iniciada no aparelho**.

## Limites e riscos (honestidade sobre o ganho)

- USB 3 permite declarar 900 mA: no melhor caso 4,5 W contra 2,5 W hoje. Cabo USB-A para USB-C sempre anuncia corrente padrão (Rp 56 kΩ).
- Não é possível fazer o PHY SuperSpeed funcionar por tentativa e erro: um valor errado em tabelas de calibração pode deixar o link instável. Cada tentativa sem hardware de teste (analisador de link) é no escuro.
- O ganho maior de carga está em USB PD (9 V) ou num carregador de parede, não no USB 3.
