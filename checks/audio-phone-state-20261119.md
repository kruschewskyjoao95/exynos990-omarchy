# Som no aparelho: estado medido (19/11/2026, kernel de produção gravado)

Queixa do proprietário: o menu de som mostra "Phone output (no audio device connected)".

## Observado no aparelho
- `cat /proc/asound/cards`: `--- no soundcards ---`. O item do menu é o sink de reserva do PipeWire/WirePlumber (`wpctl status`: nenhum dispositivo), não uma falha de configuração.
- Os dois amplificadores do alto-falante são detectados no I2C: `cs35l41 3-0040` e `3-0041`, `Cirrus Logic CS35L41 (35a40), Revision: A0`. Falta o caminho de áudio até eles: o I2S sai do bloco ABOX (DSP), sem driver no kernel. O patch `0144` (outro agente, não commitado) é só um esqueleto que enumera e loga.
- Só o kernel tem `CONFIG_SND_USB_AUDIO=y`; a porta USB-C do aparelho está em modo gadget com o cabo do computador, e um fone USB-C pediria modo host (não testado).
- Bluetooth: `hci0` existe (`rfkill`: sem bloqueio), `bluez`/`bluez-utils` **não estavam instalados** e foram instalados agora (`bluetooth.service` ativo). O controlador **não inicializa**: `hci0: setting up ROME/QCA6390`, depois `command 0xfc00 tx timeout` e `Reading QCA version information failed (-110)`, em tentativas repetidas. É o primeiro comando HCI: o chip não responde pela UART (`10840000.serial`), então não é a dessincronização descrita em `research/wifi-bt-firmware.md`.
- Pinos: `gpq0-2` (RTS) sem função de UART (`MUX UNCLAIMED`) e `gpio-720 bt-uart-rts` configurado como saída em nível baixo; o patch `0106` (`uart1_bus_single`) descrito na pesquisa não está no kernel em execução.
- Nó DT `bluetooth`: `compatible = "brcm,bcm4349-bt"` com `shutdown-gpios`, `device-wakeup-gpios`, `host-wakeup-gpios`, `max-speed`. Não verificado por que o hci_qca (e não o hci_bcm) assumiu a porta.

## Caminhos (nenhum implementado ainda)
1. Bluetooth (A2DP): corrigir a inicialização do QCA6390. Tempo desconhecido; começa por UART/RTS (0106), `shutdown-gpios` (BT_EN) e o `max-speed` do nó.
2. Fone/DAC USB-C: precisa de modo host na porta única, que é a do cabo.
3. Alto-falante interno: porte do ABOX (`research/audio.md`, estimativa de semanas), com firmware de proteção do cs35l41 antes de qualquer som.
