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

## Limites e riscos (honestidade sobre o ganho)

- USB 3 permite declarar 900 mA: no melhor caso 4,5 W contra 2,5 W hoje. Cabo USB-A para USB-C sempre anuncia corrente padrão (Rp 56 kΩ).
- Não é possível fazer o PHY SuperSpeed funcionar por tentativa e erro: um valor errado em tabelas de calibração pode deixar o link instável. Cada tentativa sem hardware de teste (analisador de link) é no escuro.
- O ganho maior de carga está em USB PD (9 V) ou num carregador de parede, não no USB 3.
