# Build, boot e instalação: sequência executável por marcos

Consulta em 16/11/2026. **Estado em 17/11/2026: bootloader já desbloqueado e LineageOS 24.0 instalado pelo proprietário com ajuda do Gemini antes deste projeto (16/11/2026, confirmado pelo proprietário); build M1 em andamento; nenhum flash deste projeto nem teste no aparelho executado.** Este documento detalha M0–M2 e a passagem para M4/M5. As verificações e nomes locais propostos abaixo são critérios deste projeto. O comportamento citado dos scripts foi lido, não comprovado no hardware.

## 1. Fixar a cadeia antes de construir

O port descreve a cadeia S-Boot → lk3rd → imagem Android contendo uniLoader → kernel/DTB → rootfs UFS. lk3rd ocupa os primeiros 2 MB da região stock `boot` e apresenta o restante como seu slot virtual `boot`. Assim, escrever `boot` via ADB e escrever o slot `boot` pelo fastboot de lk3rd são operações diferentes. O procedimento publicado instala lk3rd por uma shell Android privilegiada; `fastboot boot` só aparece **depois** dessa preparação. [Guia de flash](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/FLASHING.md).

Nesse fluxo, “imagem Android” designa o formato do contêiner de boot; o payload é uniLoader com o kernel do port, não um kernel LineageOS. Essa interpretação decorre dos arquivos fornecidos ao empacotador. [Empacotador de boot](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/package-boot.sh).

**Decisão proposta:** reproduzir Debian mínimo primeiro. LineageOS pode ser o Android atualmente instalado, mas seu nome não comprova acesso privilegiado, compatibilidade de boot ou disponibilidade do fastboot de lk3rd. A aceitação técnica do script é `adb shell id -u` retornar `0`; root disponível apenas por `su` não satisfaz essa chamada. Não alterar ROM só para preencher essa condição sem antes fechar recuperação e método de instalação. [Verificação no script](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/flash-boot.sh).

| Entrada | Referência publicada | O que falta fixar localmente |
| --- | --- | --- |
| Port r8s | `bshbsh404/galaxy-s20fe-mainline-linux`, `main` | SHA completo e hashes da série de patches |
| Kernel | `exynos990-mainline/linux`, `75138397b8f856193bf344a21a1e1e98179f0901`, base `6.12.0-rc5` | Checkout limpo e resultado de aplicar os patches do port |
| uniLoader | Prefixo `2418e06` | SHA completo resolvido e configuração r8s |
| lk3rd | Prefixo `b460741` | SHA completo, receita/saída do build r8s e limites nessa revisão |
| AOSP mkbootimg | Ferramenta indicada, sem revisão fixa | Commit e versão do Python |
| Rootfs | Debian `trixie`, ARM64 | Digest do container, repositório/snapshot e versões dos pacotes |
| Firmware | QCA6390 e DTB stock | Procedência, licenças e hashes |

As referências de kernel/uniLoader constam em [BUILDING.md](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md); lk3rd em [FLASHING.md](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/FLASHING.md). Prefixo curto publicado não equivale a pin completo validado. O [upstream lk3rd](https://github.com/exynos990-mainline/lk3rd) declara desenvolvimento inativo: atualizações desse componente terão de ser avaliadas pelo projeto.

**Entrega M0:** inventário de [03-primeira-sessao.md](03-primeira-sessao.md), backups externos legíveis, método de recuperação compatível e mapa de partições real. **Parar** se modelo, tamanho, destino de escrita, estado de bloqueio ou recuperação estiverem indefinidos.

## 2. Preparar o host sem tocar no telefone

Layout **proposto** de workspace descartável, montado como `/work` no ambiente de build:

```text
sources/port/             checkout fixado do port
cs/linux-990-fu/          kernel com a série aplicada
uniLoader/src/           checkout fixado de uniLoader
sources/lk3rd/           checkout fixado de lk3rd
boot/slk-stock.dtb        entrada privada extraída do boot stock
boot/                    imagens de RAM e UFS, em nomes distintos
rootfs/                  sd-r8s.img e ufs-root.img
out/                     módulos, manifesto e checksums
logs/                    comandos, versões e resultados
```

Esse layout conserva caminhos esperados por `package-boot.sh`: o script invoca `docker exec kbuild`, usa `/work/cs/linux-990-fu`, `/work/uniLoader/src` e `/usr/local/lib/mkbootimg/mkbootimg.py`. Gera `boot/r8s-<nome>.img` e `out/modules-<nome>.tar.gz`; o tar contém o **conteúdo** de `lib/modules/<release>`, não esse diretório externo. O mesmo script remove `/work/out/modstage`, portanto esse caminho deve ser exclusivamente descartável. [Empacotador](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/package-boot.sh).

**Tarefas propostas antes de executar:**

- Registrar arquitetura do computador, espaço livre, ferramentas e versões. Verificar compilação cruzada separadamente da execução de binários ARM64 dentro do container/chroot; se o host for x86_64, provar a execução ARM64 ou usar builder ARM64.
- Preparar container de kernel e ambiente rootfs isolados. O rootfs publicado requer container ARM64 privilegiado com loop/mount; revisar mounts para não oferecer discos reais nem diretórios pessoais à receita.
- Criar diretórios esperados; remover suposições de caminhos da máquina do autor em uma pequena adaptação versionada.
- Revisar `stat -f%z` e `shasum` no host Linux, mantendo verificações de tamanho/hash. Ensaiar ferramentas de escrita com ADB simulado e arquivos descartáveis antes do aparelho.

**Saída:** ambiente descrito por versões/digests e um manifesto que relacione fontes → configuração → firmware → artefatos. **Parar** se binário ARM64 não executar, loop não puder ser isolado ou revisão não puder ser resolvida.

## 3. Construir o conjunto kernel, DTB e módulos

O build documentado aplica `kernel/patches/*.patch`, copia `kernel/config/r8s.config`, executa `olddefconfig` e constrói `Image dtbs modules` com `ARCH=arm64` e toolchain `aarch64-linux-gnu-`. Os produtos são `arch/arm64/boot/Image` e `arch/arm64/boot/dts/exynos/exynos990-r8s.dtb`; instalar os módulos do mesmo build no staging. O guia informa `CONFIG_MODVERSIONS` desligado: igualdade de release não prova igualdade de build. [Receita](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md).

Antes disso, copiar `amss.bin`, `m3.bin` e `board-2.bin` de `ath11k/QCA6390/hw2.0` para a árvore de firmware do kernel. Extrair separadamente `slk-stock.dtb` do boot stock próprio com AOSP `unpack_bootimg`: ele vai no cabeçalho Android, enquanto o DTB r8s do kernel fica dentro de uniLoader. Não intercambiar esses dois DTBs. [Firmware e DTB stock](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/FIRMWARE.md).

**Validação proposta:** registrar log sem patches rejeitados; guardar `.config`, `kernelrelease`, hashes de `Image`/DTB/módulos e lista de arquivos. Inspecionar o DTB resultante, incluindo `/chosen/bootargs`, raiz e regiões reservadas. Confirmar que drivers necessários para alcançar a raiz estão embutidos ou presentes no initramfs. A configuração publicada habilita initrd e gzip e deixa `CONFIG_CMDLINE` vazio; isso torna a revisão do DTB/loader parte necessária da receita. [Configuração](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/kernel/config/r8s.config).

**Parar** por patch rejeitado, firmware ausente, DTB de outro modelo, módulos de outra compilação ou raiz não explicada pela cadeia de boot. Não aplicar patches diagnósticos ao baseline por conveniência.

## 4. Produzir duas imagens de boot distintas

### Diagnóstico em RAM

`build-slim-initramfs.sh` produz `/work/boot/initramfs-slim.cpio.gz`, com systemd, ferramentas básicas e módulos do kernel. O script explica um limite aproximado de 40 MB comprimidos para esse ramdisk, pois o caminho de boot envolve uma área de 64 MB. Isso é diferente do buffer de download usado pela imagem UFS. Ele tenta copiar `/work/rootfs-glue/r8s-usb-gadget` e ignora falha com `|| true`; ausência desse arquivo pode comprometer o console USB sem interromper o build. [Initramfs reduzido](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/build-slim-initramfs.sh).

**Sequência proposta:** fornecer o script gadget validado; gerar o initramfs com senha de laboratório; conferir `/init`, shell, serviços e módulos dentro do cpio; substituir `uniLoader/src/blob/ramdisk` pelo cpio gzip real; reconstruir uniLoader e empacotar `boot/r8s-ram-<id>.img`. Verificar tamanho final, headers e hashes. Conferir limite efetivo no lk3rd fixado antes do teste, sem tratar “40 MB” como garantia universal.

O empacotador de artefatos pré-compilados copia Image/DTB, mas usa o `blob/ramdisk` já existente. Portanto, trocar somente Image/DTB não seleciona automaticamente o modo RAM. [Código](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/package-prebuilt-boot.sh).

`build-initramfs.sh`, alternativa maior, copia a partição do `sd-r8s.img` a partir de offset 4 MiB, limpa fstab e cria `/init`. Não há checagem de tamanho contra o limite do loader: só escolher essa variante depois de medir a imagem inteira. [Initramfs completo](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/build-initramfs.sh).

### Raiz persistente em UFS

O boot UFS usa ramdisk placeholder gzip vazio. uniLoader recebe `blob/Image`, `blob/dtb` e `blob/ramdisk`; `r8s_defconfig` e AOSP mkbootimg produzem a imagem Android v2. Preservar na primeira reprodução os parâmetros de header/endereço publicados e registrar todos no manifesto. [Empacotamento documentado](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md).

**Saída proposta:** `boot/r8s-ufs-<id>.img`, separada da variante RAM. Não confundir esse boot com teste independente do armazenamento: ramdisk vazio pressupõe raiz acessível em UFS. **Parar** se não for possível identificar qual ramdisk e qual cmdline cada imagem carrega.

## 5. Produzir o rootfs e fechar a instalação dos módulos

`build-rootfs.sh` gera `/work/rootfs/sd-r8s.img`: por padrão 4096 MiB, MBR e ext4 com início em 4 MiB. É uma imagem intermediária, apesar do nome microSD. Configura raiz `LABEL=r8sroot`, USB ACM/RNDIS, endereço `10.42.0.2/24`, autologin root e SSH por senha. Também inclui política de suspensão e hook Wi-Fi: esses serviços precisam ser deliberadamente considerados no ensaio inicial. [Construtor rootfs](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/build-rootfs.sh).

**Lacuna explícita:** a documentação manda rodar `tools/install-modules.sh`, mas seu conteúdo não pôde ser recuperado nesta consulta. Não presumir argumentos, mountpoint ou árvore de origem. Na implementação, ler esse arquivo no checkout fixado antes de usá-lo. Resultado exigido: árvore `lib/modules/<kernelrelease>` do build selecionado dentro da raiz e índices `depmod` coerentes. Se usar o tar do empacotador, extraí-lo dentro desse diretório de release, pois ele não contém o diretório externo.

`build-ufs-image.sh` copia a partição intermediária para `/work/rootfs/ufs-root.img`, ext4 bruto de 700 MiB, sem MBR. O limite de download documentado é 805306368 bytes. Instala `r8s-growroot` com `resize2fs /dev/sda32` e supõe uma partição de aproximadamente 108 GiB; não é descoberta automática do aparelho. [Conversor UFS](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/build-ufs-image.sh).

**Validação proposta:** antes de habilitar expansão, comparar destino real, capacidade, label e cmdline. Com a imagem desmontada, verificar ext4 sem modificar; remontar somente leitura para conferir módulos, serviços e permissões. Registrar tamanho final e hash. **Parar** se os arquivos não couberem, houver inconsistência de filesystem ou destino divergente. Desktop completo entra depois do primeiro boot persistente, salvo transporte maior previamente validado.

## 6. Executar no aparelho somente após fechar M0/M1

Esta é uma sequência futura, sem comandos destrutivos para copiar:

| Ordem | Ação planejada | Evidência exigida para avançar |
| --- | --- | --- |
| 1 | Preparar recuperação, backups externos e instalação r8s de lk3rd conforme o Android/bootloader inventariado | Hashes, tamanhos e modo de recuperação conferidos; imagem lk3rd identificada |
| 2 | Instalar lk3rd pelo método revisado | Verificação de leitura e acesso ao menu/fastboot esperado |
| 3 | Inicializar **imagem RAM** temporária | Console alcançável; `uname`, cmdline, módulos e mounts registrados; nenhum mount UFS em escrita |
| 4 | Testar tela, toque, UFS em leitura e retorno ao loader | Logs sem erro impeditivo; reinício e recuperação repetíveis |
| 5 | Gravar rootfs mínimo no destino `userdata` validado | Perda de conteúdo de userdata prevista; imagem/tamanho/destino confirmados |
| 6 | Inicializar **imagem UFS** temporária | Raiz correta, módulos compatíveis, expansão concluída quando aplicável e acesso de diagnóstico |
| 7 | Tornar permanente a imagem UFS validada no slot de lk3rd | Boot a frio, cinco ciclos e retorno à imagem conhecida funcionando |

Os critérios acima são do projeto. O guia upstream descreve boot temporário, instalação em userdata e depois persistência do kernel, além de recuperação por Download se Android deixar de iniciar. [Fluxo upstream](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/FLASHING.md).

## 7. Corrigir os bloqueios dos scripts antes da primeira escrita

| Achado de leitura | Consequência e tarefa proposta |
| --- | --- |
| `flash-boot.sh` usa `stat -f%z`, exige ADB root e zera a região boot antes da imagem | Adaptar host; conferir seleção de um único aparelho; reservar esse procedimento para a instalação apropriada, sem confundi-lo com atualização do slot lk3rd |
| Snapshot de boot diferente do stock não é comparado por hash antes da escrita | Exigir backup externo completo e hash validado antes de autorizar o passo destrutivo |
| `restore-stock.sh` só compara hash registrado se a variável `want` não estiver vazia | Tornar ausência do registro um erro na futura adaptação; o comentário promete garantia mais forte que a implementação |
| Restauração por script exige ADB root funcionando | Não tratá-la como recuperação universal após falha de boot; preparar Download/firmware correspondente |

Fontes: [flash-boot.sh](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/flash-boot.sh) e [restore-stock.sh](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/restore-stock.sh). A adaptação futura precisa de ensaio com ADB simulado cobrindo destino incorreto, tamanho excedido, falta de hash, bateria abaixo do limite, falha de backup e divergência de leitura. Não ampliar a lista de partições graváveis.

## 8. Repetição em Arch ARM e pacote alpha

**Proposta de integração:** depois de M2/M3, criar rootfs Arch ARM separado usando o mesmo conjunto kernel/DTB/módulos comprovado. Reproduzir os serviços necessários por comportamento e caminhos válidos nessa base, sem copiar o bootstrap Debian como instalador Arch. Reexecutar diagnóstico RAM/UFS e testes de recuperação antes de adicionar o ambiente Omarchy.

A hipótese a validar é manter a mesma imagem de kernel para Debian e Arch: isso depende de configuração, interfaces de userspace, módulos, cmdline e localização da raiz compatíveis. O nome da distribuição sozinho não exige outro kernel nem garante que a troca de rootfs funcione.

Cada release deverá levar manifesto, checksums, log de build, configuração final, lista de pacotes, imagens RAM/UFS identificadas e guia de retorno. Blobs privados ficam em entrada local separada; nenhuma senha, chave SSH pessoal ou identificador de aparelho deve acompanhar a imagem distribuída. O limite do transporte torna a separação base mínima/pacotes de desktop uma decisão de instalação, não só de organização.

**Pendências que impedem chamar isto de receita validada:** SHA do port; resolução dos pins curtos; leitura do build r8s de lk3rd, do DTS final e de `install-modules.sh`; limites confirmados no loader fixado; execução ARM64 do host; inventário real; builds e ensaio de recuperação. O próximo trabalho concreto é fechar essas entradas e produzir a receita revisada de M1, antes de qualquer escrita.
