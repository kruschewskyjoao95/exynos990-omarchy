# Pacotes, shell e integração do desktop

Consulta: **16/11/2026**. Alvo: **SM-G780F / r8s / Exynos 990**. Pesquisa documental; nenhum pacote instalado, script upstream executado ou hardware testado.

## Entrega e decisão proposta

A entrega é **Omarchy adaptado sobre Arch Linux ARM**, executando nativamente no telefone. Deve incluir o shell real do Omarchy, sua configuração de sessão e seus temas/comandos necessários. Uma paleta sobre outro desktop pode servir ao diagnóstico, mas não conclui essa entrega. Debian permanece uma referência de funcionamento do port r8s, sem ser a distribuição final.

Proposta para a primeira integração: conservar a cadeia de boot, kernel e suporte r8s; construir rootfs Arch ARM separado; empacotar a pilha gráfica compatível; adaptar o Omarchy em poucas fronteiras explícitas. Não usar a ISO de PC como instalador Samsung. O perfil ARM da ISO seleciona `uefi.grub`, enquanto o port usa S-Boot → lk3rd → uniLoader e imagem Android contendo kernel/DTB. [Perfil da ISO](https://github.com/omacom/omarchy-iso/blob/quattro/configs/profiledef.sh), [build r8s](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md).

## O que foi verificado e o que ainda falta

Há três evidências diferentes: uma **receita** declara como compilar; um **índice de repositório** declara um pacote publicado; um **teste no r8s** comprova funcionamento naquele conjunto. Esta pesquisa obteve as duas primeiras parcialmente, nunca a terceira. Página indisponível não comprova ausência do pacote.

### Pacotes encontrados no índice Arch Linux ARM

Valores observados nas páginas oficiais abaixo, não um manifesto congelado nem garantia de que espelhos Omarchy tenham as mesmas versões. A arquitetura `any` de UWSM indica conteúdo independente de arquitetura disponível no índice ARM. As páginas têm datas de cache diferentes; resolver novamente a transação inteira antes do build.

| Nome exato consultado | Versão exibida | Arquitetura / repositório | Decisão proposta |
| --- | --- | --- | --- |
| [hyprland](https://archlinuxarm.org/packages/aarch64/hyprland) | `0.57.2-1` | `aarch64 / extra` | Referência de disponibilidade; comparar com receita Omarchy antes de escolher |
| [quickshell](https://archlinuxarm.org/packages/aarch64/quickshell) | `0.3.2-1` | `aarch64 / extra` | Não assumir equivalente ao Quickshell modificado pelo Omarchy |
| [glibc](https://archlinuxarm.org/packages/aarch64/glibc) | `2.43+r22+g8362e8ce10b2-2` | `aarch64 / core` | Base candidata; verificar artefato e requisitos reais |
| [mesa](https://archlinuxarm.org/packages/aarch64/mesa) | `1:26.2.7-1` | `aarch64 / extra` | Não substituir automaticamente Mesa r8s por esse pacote |
| [foot](https://archlinuxarm.org/packages/aarch64/foot) | `1.28.0-2` | `aarch64 / extra` | Terminal escolhido |
| [firefox](https://archlinuxarm.org/packages/aarch64/firefox) | `160.0-1` | `aarch64 / extra` | Navegador escolhido; testar Wayland e toque |
| [uwsm](https://archlinuxarm.org/packages/aarch64/uwsm) | `0.27.1-1` | `any / extra` | Preservar gestão da sessão usada pelo Omarchy |
| [networkmanager](https://archlinuxarm.org/packages/aarch64/networkmanager) | `1.58.1-3` | `aarch64 / extra` | Usar para rede do desktop |
| [sddm](https://archlinuxarm.org/packages/aarch64/sddm) | `0.21.0-7` | `aarch64 / extra` | Login escolhido; validar entrada por toque separadamente |

As consultas exatas a `/packages/aarch64/wvkbd` e `/packages/aarch64/omarchy` não retornaram conteúdo utilizável nesta ferramenta. **Disponibilidade não determinada**. Omarchy tem repositório próprio; procurar somente no índice ALARM não resolve sua instalação.

### Receitas Omarchy e referências de fonte

O projeto de pacotes documenta `pkgbuilds/<nome>/PKGBUILD`, publicação para `x86_64`/`aarch64` e canais `edge`, `rc`, `stable`, servidos em `https://pkgs.omarchy.org/<canal>/<arquitetura>`. Receitas e bancos publicados são verificações distintas. [Documentação do repositório de pacotes](https://github.com/omacom/omarchy-pkgs#omarchy-package-repository).

| Receita lida em `omacom/omarchy-pkgs/master` | Identificador observado | Implicação |
| --- | --- | --- |
| [`pkgbuilds/omarchy/PKGBUILD`](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy/PKGBUILD) | `4.5.0-2`, fonte `a948d8a6871f446b335258c827648ac5f4e9428b`, tag declarada `v4.5.0` | Candidato concreto para reproduzir a release; não é SHA da ponta de `quattro` |
| [`pkgbuilds/omarchy-settings/PKGBUILD`](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy-settings/PKGBUILD) | Mesmo `4.5.0-2` e SHA | Runtime e settings devem permanecer no mesmo conjunto de fonte |
| [`pkgbuilds/omarchy-dev/PKGBUILD`](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy-dev/PKGBUILD) | `4.0.0.r7524.g8e74d36-1`, fonte `8e74d366802a307eb20fcdff95138163de5f7d58` | Snapshot de receita servido em cache; não estabelece o `quattro` atual |
| [`pkgbuilds/hyprland/PKGBUILD`](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/hyprland/PKGBUILD) | `0.57.1-2`, `arch=(x86_64 aarch64)` | Receita inclui patches `nvidia-egl-teardown`, `wl-output-global-grace` e `monitor-rule-vrr`; difere do ALARM |
| [`pkgbuilds/quickshell/PKGBUILD`](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/quickshell/PKGBUILD) | `0.3.2.r7.g2b4501a-11`, fonte `2b4501a282689792b62e94f3fb30d8f512324fe6`, ambas arquiteturas | Inclui `load_qtquick_611.patch` e hook de verificação; difere do ALARM |

O `shell.qml` consultado começa com `OmarchyLoadPatch`; o patch Quickshell implementa tratamento correspondente no carregamento QML. Logo, usar o pacote ALARM de mesmo nome sem comparar esse comportamento seria uma hipótese adicional. Prioridade proposta: receita Omarchy e Qt do mesmo conjunto de repositórios, com teste de importação/carregamento antes de reduzir dependências. [Entrada do shell](https://github.com/omacom/omarchy/blob/quattro/shell/shell.qml), [patch Quickshell](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/quickshell/load_qtquick_611.patch).

**Pins ainda faltantes:** SHA de `omarchy-pkgs` que contém cada receita; SHA de `omarchy-iso`; SHA exato do runtime escolhido se for `quattro`; versões/binários publicados de todas as dependências e checksum dos bancos. `git ls-remote` falhou por resolução DNS no ambiente local; navegação forneceu conteúdo em cache. Os pins acima foram lidos nas receitas, sem clone e sem comprovação de um snapshot comum. Não combinar essas versões como se já fossem uma release testada.

## Compatibilidade do rootfs com Linux 6.12.0-rc5

O tarball genérico Arch ARM traz userspace e `linux-aarch64`; a própria documentação atribui ao integrador a responsabilidade pelo boot. Também documenta contas/senhas padrão e serviços de rede, que precisam ser substituídos/configurados na imagem derivada. Reaproveitar seu userspace não significa adotar seu kernel ou DTBs. [Instalação genérica AArch64](https://archlinuxarm.org/platforms/armv8/generic).

O port fixa a base do kernel em `75138397b8f856193bf344a21a1e1e98179f0901`, aplica patches e usa `kernel/config/r8s.config`. Com `CONFIG_MODVERSIONS` desativado, uma string de versão igual não garante que módulos pertençam ao build certo: preservar Image, DTB e módulos juntos. [Construção do kernel r8s](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md).

Não há evidência nesta pesquisa de que a glibc candidata exija abandonar o kernel 6.12; tampouco há prova de compatibilidade integral. O código de configuração da glibc distingue headers, mínimo geral, mínimo por arquitetura e mínimo solicitado pelo build. A receita ALARM consultada estava em `2.44+r50+g1848099f063e`, diferente do índice de binários `2.43`, impedindo atribuir automaticamente seus flags ao pacote publicado. Verificar a receita correspondente ao **artefato escolhido**, incluindo loader ELF, ABI AArch64 e exigências de kernel. Headers de userspace recentes não exigem, por si só, instalar o kernel de mesma versão. [Configuração glibc](https://github.com/bminor/glibc/blob/master/sysdeps/unix/sysv/linux/configure.ac), [receita glibc ALARM](https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/glibc/PKGBUILD).

O README atual do systemd cita baseline mínimo 5.10 e recomendado 5.14, além de flags como `CONFIG_DEVTMPFS`, `CONFIG_CGROUPS`, `CONFIG_FHANDLE`, inotify e namespaces para serviços. Isso torna 6.12 uma hipótese razoável por número de versão, **não valida a configuração r8s nem a versão de systemd do futuro rootfs**. Conferir requisitos na tag do pacote selecionado. [Requisitos systemd](https://github.com/systemd/systemd/blob/main/README).

Prova mínima proposta, antes do compositor:

1. Gerar manifesto de `glibc`, loader, `systemd`, `pacman`, bibliotecas C++ e kernel; guardar `.PKGINFO`, `.BUILDINFO`, assinatura e SHA-256 dos artefatos usados.
2. Inspecionar ELF com `readelf -h/-l/-n`; registrar arquitetura, interpretador e notas ABI quando presentes. Ausência de nota não comprova compatibilidade.
3. Executar primeiro comandos básicos no rootfs de teste e depois boot nativo: criação de processos, DNS/HTTPS, journal, D-Bus, logind, udev, rede e sessão de usuário. Chroot/QEMU no computador verifica parte do userspace, sem validar syscalls ou drivers do kernel do telefone.
4. Guardar `uname -a`, configuração do kernel, `systemd --version`, `getconf GNU_LIBC_VERSION`, `pacman -Q`, `systemctl --failed` e logs. Erros `ENOSYS`, instrução ilegal, loader ausente e falhas de unidade são bloqueadores a investigar, não motivos para trocar silenciosamente o kernel.

## Matriz de reaproveitamento

As decisões e testes abaixo são propostas deste projeto. O escopo é o conjunto de arquivos inspecionados, não todos os comandos, plugins, pacotes ou migrações existentes.

| Componente / fonte e caminho | Reaproveitar, adaptar ou excluir do MVP | Dependência/fronteira principal | Validação que libera integração |
| --- | --- | --- | --- |
| r8s: `kernel/`, `tools/`, `device/` [árvore](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux) | Reaproveitar suporte; adaptar construção e instalação ao rootfs Arch | Boot, módulos, firmware, caminhos e nomes de serviços | Boot/rede/USB repetíveis sem desktop |
| Arch ARM: tarball genérico [documentação](https://archlinuxarm.org/platforms/armv8/generic) | Reaproveitar userspace; excluir kernel genérico da cadeia ativa | Ownership, ACLs, keyring, `/boot`, contas e rede inicial | Manifesto, login seguro, init/udev e recuperação |
| Omarchy: `config/hypr/hyprland.lua`, `default/hypr/bootstrap.lua` [config](https://github.com/omacom/omarchy/blob/quattro/config/hypr/hyprland.lua), [bootstrap](https://github.com/omacom/omarchy/blob/quattro/default/hypr/bootstrap.lua) | Reaproveitar Lua e módulos; adaptar monitores/entrada/atalhos | `/usr/share/omarchy`, `~/.config`, estado de temas e API Lua do compositor | Sessão sem erros de configuração e reload funcionando |
| Omarchy: `default/hypr/omarchy.lua` [módulos](https://github.com/omacom/omarchy/blob/quattro/default/hypr/omarchy.lua) | Preservar conjunto coerente; desativar referências a apps excluídos | Módulos obrigatórios, opcionais, gestos, aparência, bindings | Cada ação exposta encontra comando e app disponíveis |
| Omarchy: `shell/`, `bin/omarchy-launch-shell` [estrutura](https://github.com/omacom/omarchy/tree/quattro/shell), [launcher](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-launch-shell) | Reaproveitar shell real, barra, menu e notificações | Quickshell/Qt, `OMARCHY_PATH`, Hyprland, journal e IPC | Uma instância, logs legíveis, menu/IPC e reinício do shell funcionando |
| Omarchy: `config/omarchy/shell.json` [configuração](https://github.com/omacom/omarchy/blob/quattro/config/omarchy/shell.json) | Adaptar widgets/dock para a tela e apps mínimos | Seleção de plugins e referências a aplicações | Botões acessíveis por toque; nenhum atalho visível sem implementação |
| Omarchy: `default/hypr/autostart.lua` [autostart](https://github.com/omacom/omarchy/blob/quattro/default/hypr/autostart.lua) | Adaptar explicitamente | Inicia shell, provisionamento, perfil de energia, monitor watch, udiskie, herdr e hook | Não iniciar componentes retirados nem provisionar indevidamente a cada login |
| Omarchy: temas e `bin/omarchy-theme-set` [aplicação](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-theme-set) | Reaproveitar mecanismo de tema, começando com um tema incluído | Estado em `~/.local/state/omarchy`, geradores e apps de destino | Tema aplicado a shell/Hyprland/Foot; troca repetida sem erro |
| Mesa r8s + receitas Mesa/Hyprland/Quickshell | Adaptar empacotamento, preservar patches necessários | DRM/KMS, render node, libdrm, EGL/GBM e Qt | Prova gráfica abaixo, incluindo renderer de hardware |
| NetworkManager + painel do shell | Reaproveitar backend/UI; adaptar nomes de interfaces | Firmware/ath11k, D-Bus, polkit, DNS; evitar dois gerentes na mesma interface | Conectar/reconectar e persistir rede sem root |
| SDDM + UWSM | Reaproveitar sessão; adaptar autenticação/tela/entrada | logind, ambiente de usuário, teclado virtual e PAM | Cinco ciclos de login/logout; recovery independente |
| `omarchy-settings` e scriptlet [receita](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy-settings/PKGBUILD), [scriptlet](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy-settings/omarchy-settings.install) | Adaptar antes de instalar | `/etc`, `/etc/skel`, initramfs, políticas e hooks | Comparação de arquivos antes/depois; boot e configs r8s preservados |
| `bin/omarchy-update`, `bin/omarchy-migrate` [update](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-update), [migração](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-migrate) | Adaptar fluxo; revisão de cada migração incluída | Transação pacman, shell IPC, estado por usuário e boot | Atualização completa, falha controlada e retorno comprovado |
| Kernel genérico, ISO/particionamento PC, Limine e hooks sem uso r8s | Excluir do caminho de instalação/boot inicial | Não correspondem à cadeia Samsung | Pacotes/hooks não podem alterar imagem de boot ativa |
| NVIDIA/Intel, suporte de notebooks específicos, jogos/FEX, IA local, impressoras e grandes suítes | Excluir do MVP por escopo | Não necessários para terminal/navegador/shell | Configs e menus mínimos não dependem desses extras |

As listas `install/omarchy-base.packages` e `install/omarchy-other.packages` são entrada para instalação/espelho e incluem aplicações e suporte opcional além da sessão. Não equivalem a um fechamento mínimo de dependências; sua presença não manda instalar todos os kernels/drivers em ARM. [Lista base](https://github.com/omacom/omarchy/blob/quattro/install/omarchy-base.packages), [lista adicional](https://github.com/omacom/omarchy/blob/quattro/install/omarchy-other.packages).

## Pilha gráfica: fronteiras e testes

O port relata tela pelo driver `exynos990-dpu` e Mali-G77 com Panfrost; o guia instala Mesa próprio em `/opt/mesa-g77`. Não foi recuperado o conteúdo de `mesa/README.md` nesta consulta; SHA/versão exatos de Mesa e subconjunto necessário dos patches continuam pendentes. Não copiar os binários Debian para o Arch: reconstruir a mesma fonte/patches contra as bibliotecas do rootfs candidato. [README r8s](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux), [seção Mesa do build](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md#4-mesa).

A documentação Mesa distingue a GPU do controlador de tela e explica o papel de `kmsro`; sua tabela consultada não lista G77. Portanto, suporte upstream à família Mali não substitui a evidência específica do port. Vulkan experimental não é critério para liberar o desktop inicial. [Panfrost/Mesa](https://docs.mesa3d.org/drivers/panfrost.html).

Hyprland ALARM depende de Aquamarine, libdrm, libinput, Lua, Mesa, Wayland e outras bibliotecas. Isso oferece uma lista concreta para resolver ABI, mas não prova que o compositor aceita todas as capacidades de scanout/sincronização do DPU r8s. [Dependências Hyprland](https://archlinuxarm.org/packages/aarch64/hyprland#dependencies).

Sequência de testes proposta, salvando saída e versões em cada passo:

1. **DRM/KMS e entrada:** identificar `/dev/dri/card*`, `/dev/dri/renderD*`, drivers e conectores; conferir modos e eventos de toque. Não fixar `card0` por suposição. Inspecionar com `modetest`/ferramenta equivalente e `libinput`; os pacotes que fornecem esses executáveis ainda devem ser resolvidos.
2. **EGL/GBM:** testar o Mesa reconstruído com utilitário EGL/Wayland e compositor simples de diagnóstico. Registrar bibliotecas efetivamente carregadas, renderer, extensões e falhas de importação de buffers. Sucesso no Debian é apenas comparação, não validação do Arch.
3. **Hyprland mínimo:** sem shell e plugins adicionais, testar modos, escala, toque e duas janelas. Registrar `hyprctl version`, `hyprctl -j monitors`, `hyprctl -j devices` e logs. Se a CLI da versão escolhida mudar, ajustar os comandos após consultar seu help.
4. **Shell Omarchy real:** carregar Lua, Quickshell modificado, tema e painel de rede. Testar importações QML, IPC, alteração de tema, diálogos polkit e reinício da sessão. Não usar `llvmpipe`, `softpipe` ou fallback Qt por software como comprovação de aceleração; registrar renderer em cada processo relevante.
5. **Fluxo móvel:** ligar Wi-Fi → abrir Firefox → digitar URL/senha por teclado virtual → abrir Foot → alternar/fechar janelas → logout/login. Testar retrato e rotação manual, coordenadas do toque, escala fracionária escolhida e tela apagada/acesa. Suspensão profunda fica desativada até prova independente de retorno.

Falha gráfica deve separar DRM/scanout, Mesa/renderização, compositor e shell. Desativar efeitos pode ajudar a isolar, mas não substituir a resolução de erros de importação/sincronização. Não ativar variáveis de contorno globais sem registrar erro, escopo e condição de remoção.

## Conjunto mínimo selecionado para a primeira tentativa

**Proposta de seleção, não comando de instalação nem lista já resolvida.** Pacman deverá fechar dependências transitivas; comparar essa resolução com as receitas e imports realmente usados. Pacotes sem versão na tabela inicial continuam com disponibilidade/versão ARM pendentes, mesmo quando aparecem numa receita upstream.

| Grupo | Nomes candidatos e seleção | Condição |
| --- | --- | --- |
| Base Arch ARM | `base`, `archlinuxarm-keyring`, `ca-certificates`, `openssh`, `sudo`, `e2fsprogs` | Resolver metapacote/base e suas dependências; rootfs sem kernel genérico ativo |
| Sessão | `hyprland`, `quickshell`, `uwsm`, `sddm`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk` | Preferir par de receitas Omarchy compatível; revalidar nomes dos portais e suas dependências |
| Shell/runtime Omarchy | `omarchy`, `omarchy-settings`, `omarchy-keyring`, `omarchy-themes-intros`, `omarchy-speedtest`, `ttf-jetbrains-mono-nerd-basic` | Runtime/settings reconstruídos com adaptação r8s; confirmar publicação de cada artefato e mesma fonte |
| Dependências diretas declaradas do runtime | `wireplumber`, `pipewire`, `gnome-keyring`, `gum`, `jq`, `git`, `perl`, `fakeroot`, `pacman-contrib` | Manter inicialmente; ausência de áudio interno não elimina dependências de sessão/IPC |
| Dependências diretas de settings | `bash`, `curl`, `sudo`, `hicolor-icon-theme`, `plymouth` | Preservar resolução inicialmente; impedir integração de boot incompatível antes da instalação |
| Rede | `networkmanager`; backend Wi-Fi resolvido pelo pacote | Uma configuração por interface; coexistência do USB recovery planejada |
| Aplicações | `foot`, `firefox`, `xdg-user-dirs`, `xdg-utils`, `wl-clipboard`, `noto-fonts`, `noto-fonts-emoji` | Firefox definido como navegador dos launchers/dock; confirmar pacotes não consultados |
| Toque/brilho | `brightnessctl`, **`wvkbd` como candidato inicial de teclado virtual** | Disponibilidade/build de wvkbd e compatibilidade de protocolos pendentes; testar também no login/bloqueio |
| Qt e gráficos | `qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-svg`; `mesa` reconstruído para r8s | Resolver Quickshell/Qt como conjunto; adicionar módulos requeridos pelos plugins mantidos, como `qt6-multimedia`/`qt6-imageformats`, após conferir imports |
| Integração local proposta | `linux-r8s`, `r8s-support`, `mesa-r8s` | Nomes **novos propostos**, ainda sem receitas; definir ownership/`provides`/`conflicts` e arquivos antes de criar pacotes |

As dependências diretas acima vêm das receitas `omarchy`/`omarchy-settings`; a receita runtime também pode adicionar `omarchy-security-functions` conforme a fonte empacotada. Isso precisa ser computado a partir do pacote final, não apenas do primeiro bloco `depends`. A dependência ARM explícita observada é NetworkManager; Limine/Snapper aparecem no ramo x86 dessa receita. [Receita runtime](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy/PKGBUILD), [receita settings](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy-settings/PKGBUILD).

O wvkbd é candidato por ser um teclado virtual Wayland com fonte disponível; essa escolha não afirma integração automática com o shell, campos de senha, SDDM ou bloqueio. A alternativa só deve ser escolhida após verificar a falha concreta. Até teclado virtual e controles por toque funcionarem, há apenas uma sessão de diagnóstico com teclado USB, não o MVP móvel. [Fonte wvkbd](https://github.com/jjsullivan5196/wvkbd).

Barra inicial proposta: menu, workspaces, relógio, rede, brilho/energia e notificações; dock somente terminal e navegador. Ocultar Bluetooth/áudio interno enquanto indisponíveis; remover ações de update/reset não adaptadas. Essa configuração usa os mecanismos do próprio shell; não substitui o shell por uma implementação nova. O JSON upstream inclui widgets e aplicativos adicionais, justificando revisar referências. [Configuração do shell](https://github.com/omacom/omarchy/blob/quattro/config/omarchy/shell.json).

## Empacotamento, instalação e atualização

1. **Resolver fora do telefone.** Preparar diretório de build com configuração pacman AArch64 e canal coerente. Não alterar pacman do computador nem executar instalador. Consultar `pacman -Si` usando banco/configuração isolados, registrar `%NAME%`, `%VERSION%`, `%ARCH%`, `%DEPENDS%`, `%PROVIDES%`, `%CONFLICTS%`, filename, checksum e assinatura. Erro de download/banco deve aparecer como “consulta falhou”, não “pacote ausente”. Os espelhos ALARM usados pela ISO diferem por canal. [ISO ARM](https://github.com/omacom/omarchy-iso#aarch64).
2. **Congelar entradas.** Fixar fontes Omarchy/runtime/settings/pacotes e suporte r8s; guardar os bancos e artefatos necessários. Uma lista de nomes sem versões e arquivos não reproduz um sistema rolling release. Prioridade de repositório importa quando ALARM e Omarchy publicam o mesmo nome.
3. **Adaptar receitas existentes.** Usar runtime/settings como base, sem inventar um instalador completo. A receita settings instala arquivos em `/etc`, seeds em `/etc/skel` e sobrescritas aplicadas pelo scriptlet. Auditar também hooks ALPM, serviços e opções de initramfs da fonte escolhida; editar só as partes incompatíveis. [Receita settings](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy-settings/PKGBUILD), [aplicação das sobrescritas](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy-settings/omarchy-settings.install).
4. **Definir propriedade de arquivos.** Kernel/DTB/módulos e integração r8s devem ter donos claros. Para Mesa, escolher entre pacote substituto com metadados completos ou árvore isolada com ambiente limitado à sessão; não sobrepor `/usr/lib` por cópia manual. Qualquer substituto precisa satisfazer também dependências versionadas/SONAME, não apenas `provides=mesa`.
5. **Provisionar usuário com estado correto.** Revisar `omarchy-provision-user`, `install/user/` e primeiro login. `--first-install` marca migrações embarcadas como concluídas; só é correto quando a imagem já contém o estado equivalente. Não marcar migrações arbitrariamente para esconder falhas. [Provisionamento](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-provision-user).
6. **Reusar a extensão de plataforma existente.** `omarchy-lifecycle-dispatch` já separa operações de setup, update, provisionamento e reset. Hoje ARM genérico é no-op e mantém caminhos genéricos dos chamadores. Registrar r8s e sua implementação é uma proposta; não existe suporte Exynos comprovado nesse dispatcher. Preservar as verificações de ownership/permissões e privilégios ao estendê-lo. [Contrato](https://github.com/omacom/omarchy/blob/quattro/docs/lifecycle-dispatch.md), [dispatcher](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-lifecycle-dispatch).
7. **Não confundir sucesso com boot validado.** `omarchy-update-boot` chama o lifecycle `update-verify`; se não há implementação para a plataforma, pode terminar sem verificar arquivo Samsung algum. A implementação r8s deverá verificar seus próprios artefatos/manifesto, sem gravar flash durante uma atualização genérica de aplicativos. [Verificador atual](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-update-boot).
8. **Atualizar por conjuntos testados.** O fluxo upstream atualiza pacotes antes de migrações, reinicia o shell quando necessário e depois verifica boot. Auditar todas as migrações efetivamente incluídas antes de liberar esse fluxo; preservar ordem e tratamento de falhas. Não propor congelamento permanente de bibliotecas isoladas ou atualização parcial como política. [Fluxo de atualização](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-update), [executor de migrações](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-migrate).
9. **Retorno independente.** Manter imagem/artefatos anteriores e recovery USB. Snapshot de rootfs não prova retorno do boot/kernel e depende do filesystem escolhido; o rootfs r8s de referência usa ext4. Ensaiar atualização e rollback em imagem descartável antes do telefone. [Construção do rootfs r8s](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/build-rootfs.sh).

## Evidência necessária para encerrar esta etapa

- Manifesto resolvido de todos os pacotes selecionados, com canal/arquitetura/versão/hash/assinatura; dependências ausentes identificadas nominalmente.
- Uma fonte fixa para runtime e settings, receitas fixas para Hyprland/Quickshell/Qt/Mesa e lista dos patches r8s aplicados.
- Revisão concreta de cada hook/migração presente na imagem; diff dos arquivos de sistema modificados por instalar/atualizar settings.
- Boot nativo Arch ARM, renderer de hardware e shell Omarchy comprovados no SM-G780F.
- Fluxo de terminal/navegador/rede executado por toque, login/bloqueio utilizáveis e recuperação sem depender da sessão gráfica.
- Uma atualização do conjunto experimental e um retorno à imagem anterior, com logs e estado dos artefatos de boot.

**Limites (atualizado em 17/11/2026):** a consulta preliminar de metadados `.db` do canal `stable/aarch64` foi registrada em [packages-aarch64.md](../manifests/packages-aarch64.md) e [packages-aarch64-stable.tsv](../manifests/packages-aarch64-stable.tsv) (108 pacotes resolvidos, 1408,1 MiB instalados; 23 deps por soname pendentes de `pacman -Sy` AArch64 real). O rootfs mínimo base Arch ARM (`out/rootfs/ufs-root.img`, 160 pacotes sem kernel genérico) foi gerado por `packaging/build-env/build-arch-rootfs.sh`, e a receita pós-boot `packaging/omarchy/install-omarchy-r8s.sh` (`--dry-run` ok) está em revisão (item 5 de `COORDENACAO.md`). Continuam pendentes o empacotamento Mesa r8s (`packaging/mesa-g77/`), a auditoria completa de hooks/migrações e **todos** os testes no SM-G780F.
