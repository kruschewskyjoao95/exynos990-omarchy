# Manifesto preliminar de pacotes AArch64 (`stable`)

Gerado em: **2026-11-16** a partir dos bancos reais publicados pelo canal `stable` definido em `omacom/omarchy-iso` (`configs/pacman-online-aarch64-stable.conf`):

- `[omarchy]`: `https://pkgs.omarchy.org/stable/aarch64/omarchy.db` (`Last-Modified: Tue, 17 Nov 2026 01:50:31 GMT`, ETag `"ca1467eca8dd5f123156e7d80a3f0fb9"`)
- `[core]`, `[extra]`, `[alarm]`, `[aur]`: `https://arm-stable-mirror.omarchy.org/aarch64/<repo>/<repo>.db`

> **Escopo:** consulta direta dos metadados `.db` para o conjunto de 50 pacotes sementes selecionados em `roadmap/06-pacotes-e-desktop.md`. O fechamento transitivo abaixo resolveu **108 pacotes** nomeados (`467.5 MiB` comprimidos; `1408.1 MiB` instalados, **antes** de resolver `23` dependências virtuais por soname `lib*.so` em um `pacman` AArch64 real).

## Achados críticos que resolvem lacunas de `06-pacotes-e-desktop.md`

1. **`wvkbd` não existe** nos repositórios `omarchy-stable`, `core`, `extra`, `alarm` ou `aur`. Alternativas verificadas: compilar `wvkbd` (`4ae78249f39e1c9ce67a939d338aab2ad1e3d919`) no repositório local `[platform]`, ou testar `squeekboard` (`1.43.1-6`, disponível em `aarch64/extra`, assinado por PGP).
2. **`omarchy-security-functions` é um virtual provide** fornecido por `omarchy-settings` (`4.5.0-3`, `%PROVIDES%`), não um pacote separado.
3. **Orçamento de tamanho em UFS fastboot:** somente os 108 pacotes já somam **1408.1 MiB** instalados, excedendo com folga o limite de `700 MiB` de `ufs-root.img` (buffer `0x30000000` = `768 MiB` do `lk3rd`). Fica comprovada a necessidade de instalar uma base mínima Arch primeiro, executar `r8s-growroot` (`resize2fs`) e só depois instalar o desktop.
4. **Alinhamento Qt / Quickshell / Hyprland no canal `stable`:** `qt6-base` está em `6.12.0-3`, `quickshell` em `[omarchy]` está em `0.3.2.r7.g2b4501a-1` (sobrepondo `0.3.2-1` do `extra`), `hyprland` em `[omarchy]` está em `0.56.2-7` (sobrepondo `0.56.2-4` do `extra`), e `omarchy` / `omarchy-settings` estão em `4.5.0-3`.
5. **Assinaturas no banco `[omarchy]`:** `omarchy.db.sig` retornou `404 Not Found` e as entradas de `omarchy.db` não trazem `%PGPSIG%` embutido por pacote (`pgpsig=False`), mas as assinaturas destacadas `.pkg.tar.zst.sig` existem no servidor (`omarchy-4.5.0-3-aarch64.pkg.tar.zst.sig` retornou `200 OK`, 119 bytes). Isso explica `SigLevel = Required DatabaseOptional` em `pacman-online-aarch64-stable.conf` e exige `omarchy-keyring` + verificação SHA-256 no build isolado.
6. **Nenhum kernel genérico puxado pelo fechamento:** `linux*` não apareceu nas dependências transitivas das 50 sementes.

## Pacotes sementes resolvidos

| Pacote | Repositório vencedor | Versão | Arch | PGP no `.db` | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `base` | `core` | `3-3` | `any` | `sim` | `66af0072b148b2607e3a36b550a20811f1935688c87b807e69297eb585ead483` |
| `archlinuxarm-keyring` | `core` | `20240419-2` | `any` | `sim` | `3cb36869edfe413672a6e932cc55d7f8386e1a9d3b38663cfb3bc6fe0d146e21` |
| `ca-certificates` | `core` | `20240618-1` | `any` | `sim` | `09cfa7af79ca8120572e737c34080580ddc50c5e33a03a686c5c55032f02b575` |
| `openssh` | `core` | `10.6p1-2` | `aarch64` | `sim` | `1e24b7d33675f3ef40517db4b968ee442c04bb48a731eccfc7d54d18c3b3fb8b` |
| `sudo` | `core` | `1.9.17.p2-6` | `aarch64` | `sim` | `3e90ee7aa3b5526a155396f3baa6305e37eed317db674cc077312cc386d5b0bd` |
| `e2fsprogs` | `core` | `1.47.4-1` | `aarch64` | `sim` | `153046071f8abf1caf546a0352c7d268fb07a5b0ba0abd996de382adc8692842` |
| `hyprland` | `omarchy` | `0.56.2-7` | `aarch64` | `não (.sig destacado; db sem %PGPSIG%)` | `e803467584537b9e1c5dfdac80b71c2e4bb4829ed23c084c143dcfe93f1dbce5` |
| `quickshell` | `omarchy` | `0.3.2.r7.g2b4501a-1` | `aarch64` | `não (.sig destacado; db sem %PGPSIG%)` | `e1227d2930f84b78284cdffab8331e6a47632b2f65ee64945d785da1eb659fef` |
| `uwsm` | `extra` | `0.27.1-1` | `any` | `sim` | `bc736d4c76557e3b920e93d01710ebd84c546abfb136f82b72a25304eff571e6` |
| `sddm` | `extra` | `0.21.0-7` | `aarch64` | `sim` | `637f0b1dd727a695719b3e57102a9c071ce9eaf033a0fb0bb8f850bbec7e706c` |
| `xdg-desktop-portal-hyprland` | `extra` | `1.4.1-2` | `aarch64` | `sim` | `afbe5116a25a58093d72f20640ad81a10140e363f7caedd300d110e9232ab006` |
| `xdg-desktop-portal-gtk` | `extra` | `1.15.3-2` | `aarch64` | `sim` | `5a0ceadd58044b892142bd01a7417759585839b8e438b5ac76c8b784aca4cffd` |
| `omarchy` | `omarchy` | `4.5.0-3` | `aarch64` | `não (.sig destacado; db sem %PGPSIG%)` | `d367067c1e35d6e99f7cd921e0a55ec6e46cb0d2bc681b1a4b39254c8c0416e7` |
| `omarchy-settings` | `omarchy` | `4.5.0-3` | `aarch64` | `não (.sig destacado; db sem %PGPSIG%)` | `2a81decbaeb873a354f2b9728cd0dfc8b633af101eed98e3945e2b6bf55c8c58` |
| `omarchy-keyring` | `omarchy` | `20251027-1` | `any` | `não (.sig destacado; db sem %PGPSIG%)` | `cce48c07cfc2b97e198df1bc81705db2921685032fe39f18b4ddfd84264b5967` |
| `omarchy-themes-intros` | `omarchy` | `2026.10.14-1` | `any` | `não (.sig destacado; db sem %PGPSIG%)` | `d748591bc725de043f6ce1895b1015af3085037ab4e5f1af58f039305e1d5d9a` |
| `omarchy-speedtest` | `omarchy` | `0.2.1-1` | `aarch64` | `não (.sig destacado; db sem %PGPSIG%)` | `0fe8413b0da314035fd68aee697b6d4b7e50cde5f2413920351be63719aafb7c` |
| `ttf-jetbrains-mono-nerd-basic` | `omarchy` | `3.5.1-2` | `any` | `não (.sig destacado; db sem %PGPSIG%)` | `c574e6266139fd24f668301d39d9faab386d7041ad3952b3012a2480e09cff0c` |
| `wireplumber` | `extra` | `0.5.18-1` | `aarch64` | `sim` | `2410813c8b3eba26598b90b260171ac884af59f8dc1441112eee80f1873b628b` |
| `pipewire` | `extra` | `1:1.6.9-1` | `aarch64` | `sim` | `d711f2ba44cf9be3800b168f1d68d7791e2838c2bbefde26deff56a26eaccae2` |
| `gnome-keyring` | `extra` | `1:51.1-1` | `aarch64` | `sim` | `b452dbe568dbdf7661f9239ec3cf54a157c0f18b750a0f5e4393c5b8ee3dfc22` |
| `gum` | `extra` | `2.0.2-1` | `aarch64` | `sim` | `fa8784c1bf3b740fcd68df559fae4ba2ff44cf9008b5b27a1777890118f71322` |
| `jq` | `extra` | `1.8.2-1` | `aarch64` | `sim` | `a785a170c28f88b03c1190bd8898c4b2f2ca97839d5b277396e86f2cb107041a` |
| `git` | `extra` | `2.56.0-1` | `aarch64` | `sim` | `b152a20edb215e98cada4b2dfbd02a9e925bda0b2de6ac1441e9e60b6698d3b5` |
| `perl` | `core` | `5.44.0-1` | `aarch64` | `sim` | `9b2156550793a373a7a288edc9143d20918bfc0503c78060ef6677926f04f4e2` |
| `fakeroot` | `core` | `1:1.37.2-3` | `aarch64` | `sim` | `ae7a1e0df8abd196f5d54f8206db363e3f9ad0b7157fca026729698ccf866ad0` |
| `pacman-contrib` | `extra` | `1.13.1-1` | `aarch64` | `sim` | `7f89d02bae727950f543ec969145212b93abea947675de27280c6978cfe9b946` |
| `bash` | `core` | `5.3.20-1` | `aarch64` | `sim` | `e660aa3506d29ba0284c97467712ca6cbcf261bb5bc5917e14c96462aad186d6` |
| `curl` | `core` | `8.23.0-1` | `aarch64` | `sim` | `55078cc1416504596d5c31fbd7b5fc21c63f333d476cc5907ceecfcb03b99a92` |
| `hicolor-icon-theme` | `extra` | `0.18-1` | `any` | `sim` | `cdba2a3dba1dc73a10a1e2a4ac0da06deafa92ac243d81e127a1fcdafbe4a588` |
| `plymouth` | `extra` | `26.134.222-3` | `aarch64` | `sim` | `e0cca2deddd0af9557fa4686b1fc94180cfa34d14aed6b1c0d594b992f4666cf` |
| `networkmanager` | `extra` | `1.58.1-2` | `aarch64` | `sim` | `f33cae0f6f19f33eea879cec1db3fe7c90d0b80931e8f5b67b9391adf7185754` |
| `foot` | `extra` | `1.28.0-2` | `aarch64` | `sim` | `f941e7955c4ac814e99c3f2f91179c64c9de0c8fe26e3ab341e911e8cdbd83b6` |
| `firefox` | `extra` | `158.0-1` | `aarch64` | `sim` | `3b9e5cedd05c255e9c50a2b0d4a9fd8ba353515cf04c9a7e5efdcab0d6c43665` |
| `xdg-user-dirs` | `extra` | `0.20-1` | `aarch64` | `sim` | `249c5662c50da333e7cf5242d3c32306ef7780c9b8196060e91d46a75f49c9c5` |
| `xdg-utils` | `extra` | `1.2.1-2` | `any` | `sim` | `afd760ce97e18f354c5893038327c70b72053c23b41e609c5351c5c22fc84cd8` |
| `wl-clipboard` | `extra` | `1:2.3.0-1` | `aarch64` | `sim` | `723a63b140e00085a533ebb1ec36fa9305b5e6cbd8fb80c0521fbeff77a72982` |
| `noto-fonts` | `extra` | `1:2026.10.01-1` | `any` | `sim` | `bdc5bc01c4c93c32bf7db68dc83643e95c26b2c2fcb36708a80b3bf33c02ac8c` |
| `noto-fonts-emoji` | `extra` | `1:2.051-1` | `any` | `sim` | `082ff807f21b7dd55538a6b202eea32dc3fd0792ac78d908e30631cc7951e552` |
| `brightnessctl` | `extra` | `0.5.1-3` | `aarch64` | `sim` | `f2a4f173cc826dc2917402e4ea40dac4ae0d44557dfdd6a59a2e1a45b88edb48` |
| `squeekboard` | `extra` | `1.43.1-6` | `aarch64` | `sim` | `e7474f6363b9bca89ac317263ba53d4d31fda763c630aada9dde7087916c20a9` |
| `qt6-base` | `extra` | `6.12.0-3` | `aarch64` | `sim` | `2777135b375ba82250896fa9a993926bf3c05b59dd22217f63d6a1391c1b4c31` |
| `qt6-declarative` | `extra` | `6.12.0-1` | `aarch64` | `sim` | `410a29bc88fb004f4c1b5c8d2b08bf6d2d27c5028ebd13447e7ff67134c94940` |
| `qt6-wayland` | `extra` | `6.12.0-1` | `aarch64` | `sim` | `37d8367518085adb00ccd533363e7a58310c6810fc97ca622270ef770dccdf2f` |
| `qt6-svg` | `extra` | `6.12.0-1` | `aarch64` | `sim` | `cd03acc2075a19cbfae8ae982954fcc92846855cb9e30ed04e90523f7fcc7cb3` |
| `qt6-multimedia` | `extra` | `6.12.0-1` | `aarch64` | `sim` | `e6b090815abc7777b2949ba5dcaa2e6eca5f3ef265fa8bf2fd33ff7e94701338` |
| `qt6-imageformats` | `extra` | `6.12.0-1` | `aarch64` | `sim` | `666f6c18c62b9a2787423ecc179cfa1ccaf6e322c9dab3cb8650d38fd1f910cd` |
| `mesa` | `extra` | `1:26.2.5-1` | `aarch64` | `sim` | `a5a52d9989fdf6091e671661a7aa350542131da5a2ff1b42060425c0c0f9e775` |
| `libdrm` | `extra` | `2.4.134-1` | `aarch64` | `sim` | `d4173d7adc60d32d389e44e976447962c31bc23ff9a2153539bd8ad766e307b8` |
| `egl-wayland` | `extra` | `4:1.1.24-1` | `aarch64` | `sim` | `0abd7781365148f764311b0ccd9bc20d7c6208aca77f25813b08a07e467f49ce` |

## Lista completa resolvida (108 pacotes)

Ver tabela completa com tamanhos e nomes de arquivo em [packages-aarch64-stable.tsv](packages-aarch64-stable.tsv).

## Dependências por soname ainda pendentes de resolução via `pacman -Sy` AArch64

As 23 entradas abaixo são dependências `lib*.so` (resolvidas pelo `pacman` real a partir do índice completo de arquivos/sonames durante o build em chroot AArch64):

`libgio-2.0.so=0-64`, `libgobject-2.0.so=0-64`, `libhyprcursor.so=0-64`, `libhyprgraphics.so=4-64`, `libhyprlang.so=2-64`, `libhyprutils.so=13-64`, `libhyprwire.so=3-64`, `liblcms2.so=2-64`, `libEGL.so=1-64`, `libGLESv2.so=2-64`, `libxkbcommon.so=0-64`, `libpango-1.0.so=0-64`, `libpangocairo-1.0.so=0-64`, `libpixman-1.so=0-64`, `libre2.so=11-64`, `libtomlplusplus.so`, `libuuid.so=1-64`, `libwayland-server.so=0-64`, `libdisplay-info.so=3-64`, `libseat.so=1-64`, `libudev.so=1-64`, `libwayland-client.so=0-64`, `libLLVM.so=23.1-64`
