# Arch persistente instalado — 17/11/2026

Autorização do proprietário nesta sessão ("pode gravar"). Aparelho SM-G780F/r8s, lk3rd já instalado, mapa `sda13`=lk3rd 2 MiB, `sda33`=boot 57 MiB, `sda32`=userdata.

## Causa da falha anterior e correção

`fastboot flash userdata` com o ext4 cru era recusado antes de escrever: em `sources/lk3rd/lib/gpt/gpt.c` (`gpt_write_part`), partição sparse-ext4 só aceita imagem com magic `0xED26FF3A` (sparse Android) via `write_compressed_ext4`. Correção: `img2simg out/rootfs/ufs-root.img out/rootfs/ufs-root.sparse.img` (548 MiB, SHA-256 `ccf930db759d00b62f64588c753252d8dbed5e09e26fe4a544de24be1d33c351`); ida e volta com `simg2img` + `cmp` idêntica ao original (`a2bcc167…`).

## Gravação e conferência

1. `fastboot getvar`: product `r8s - lk3rd`, max-download-size `805306368`.
2. `fastboot flash userdata out/rootfs/ufs-root.sparse.img`: Sending OKAY 12,9s, Writing OKAY 3,4s.
3. Boot em RAM (`r8s-ram.img` `fe07490f…`): leitura de `/dev/sda32` em duas metades (blocos 0–86 e 87–174 de 4 MiB) com hashes iguais aos da imagem no host (`6df3a2b3…`, `a966d4e7…`); primeiros 64 MiB `4aaa0009…` idem. Antes disso, a tentativa de rede tinha deixado só os primeiros 4 KiB (`86799d60…`) — substituídos pela gravação sparse.
4. `fastboot flash boot out/boot/r8s-ufs.img` (`2cf80ae1…`): OKAY. `fastboot reboot`.

## Sistema no ar (SSH via USB 10.42.0.2, chave do host)

- `Linux r8s-arch 6.12.0-rc5-next-20241104-r8s aarch64`, `systemctl is-system-running` = `running`, sem unidades failed na amostra.
- Raiz `/dev/root` ext4 rw; `df /` = 107G (growroot expandiu os 700 MiB para a partição toda; serviço já `disabled` após executar).
- `/usr/lib/firmware/qca/htbtfw20.tlv` e `htnv20.bin` presentes.

## Limites

Primeiro boot apenas. Faltam: cinco boots consecutivos, rede Wi-Fi/toque reais, sessão gráfica/Omarchy (instalação via pacman é o passo seguinte), energia/temperatura e ensaio de recuperação com o mapa atual. UFS com desgaste `0x0B` continua sendo o risco de fundo; nenhum erro de escrita apareceu nestas gravações.
