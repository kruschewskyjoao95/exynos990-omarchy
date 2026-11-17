# Omarchy ARM64 sobre o S20 FE Exynos

Consulta: **2026-11-16**. Alvo do projeto: **SM-G780F / Exynos 990**.

## Conclusão

O Omarchy atual **não é exclusivamente x86_64**. Há infraestrutura ARM64, mas isso não estabelece suporte ao S20 FE. A adaptação deve começar pela camada de desktop sobre a distribuição já validada no aparelho; trocar o rootfs por Arch Linux ARM é uma etapa posterior, preservando o kernel, DTB, firmware e caminho de boot específicos do telefone.

## O que as fontes demonstram

| Área | Evidência oficial | Consequência para o projeto |
| --- | --- | --- |
| Arquiteturas | O detector distingue `x86`, `aarch64`, `aarch64-apple`, `aarch64-qualcomm`, `aarch64-n1x` e `aarch64-gb10`. Há fallback genérico para `aarch64`, mas nenhuma identificação Exynos nesse arquivo. | Ser classificado como ARM64 não instala os drivers ou a integração Samsung. [Detector](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-hw-platform) |
| Imagens ARM | O README do gerador documenta ISO `-aarch64.iso`, kernel `linux-omarchy`, repositório ARM do Omarchy e espelhos Arch Linux ARM separados por canal. | O trabalho é de plataforma e integração, não simplesmente recompilar tudo para ARM. [Gerador, seção aarch64](https://github.com/omacom/omarchy-iso#aarch64) |
| Boot | O perfil seleciona `uefi.grub` em aarch64; o caminho BIOS/syslinux fica no outro ramo. | A ISO ARM exige um ambiente de boot que ainda teria de ser comprovado no telefone. Não é uma imagem Android `boot.img`. [Perfil](https://github.com/omacom/omarchy-iso/blob/quattro/configs/profiledef.sh) |
| Instalação | A ISO grava uma imagem btrfs pré-construída na partição de destino e configura o sistema em chroot. O manual informa criptografia padrão e apagamento do disco na opção de disco inteiro. | Não executar esse fluxo sobre o armazenamento Samsung como tentativa de port. [Gerador](https://github.com/omacom/omarchy-iso), [manual](https://github.com/omacom/omarchy/blob/quattro/manual/02-getting-started.md) |
| Apple | O detector reconhece Apple Silicon, enquanto o gerador exclui Macs Apple Silicon da instalação por ISO e remete à instalação a partir do macOS. O manual de Macs ainda diz que M-series não é diretamente suportado. | Código para Apple não equivale a uma declaração consistente de suporte final, tampouco cobre Exynos. [Detector](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-hw-platform), [gerador](https://github.com/omacom/omarchy-iso#aarch64), [manual Mac](https://github.com/omacom/omarchy/blob/quattro/manual/44-mac-support.md) |

## Pacotes e configuração

A lista base inclui Hyprland, Foot, Qt6/Quickshell, UWSM, SDDM, NetworkManager e aplicações próprias; portanto, a experiência completa vai além de um conjunto de dotfiles. A lista adicional inclui kernels, Limine e pacotes de hardware específicos. Sua presença numa lista não prova disponibilidade ou funcionamento de todos eles no S20 FE. [Pacotes base](https://github.com/omacom/omarchy/blob/quattro/install/omarchy-base.packages), [pacotes adicionais](https://github.com/omacom/omarchy/blob/quattro/install/omarchy-other.packages).

O gerador usa espelhos ARM próprios (`arm-stable-mirror.omarchy.org`, `arm-rc-mirror.omarchy.org`, `arm-mirror.omarchy.org`) e configurações `pacman-online-aarch64-<canal>.conf`. **Recomendação:** não copiar o `pacman.conf` x86 do computador anfitrião; resolver cada pacote contra a arquitetura e o canal escolhidos, verificando assinatura, ABI e procedência. Não misturar pacotes pacman ao rootfs Debian. [Repositórios ARM](https://github.com/omacom/omarchy-iso#aarch64).

O `quattro` consultado usa **`hyprland.lua`**, carrega bootstrap de `/usr/share/omarchy`, módulos `default.hypr.*` e arquivos locais de monitor, entrada, atalhos, aparência e autostart. Copiar só o arquivo principal deixa dependências ausentes; também não se deve pressupor compatibilidade com o Hyprland da distribuição do telefone. [Configuração principal](https://github.com/omacom/omarchy/blob/quattro/config/hypr/hyprland.lua), [módulos carregados](https://github.com/omacom/omarchy/blob/quattro/default/hypr/omarchy.lua).

As paletas em `colors.toml` e os fundos são o reaproveitamento inicial mais simples. O próprio Omarchy gera configurações de aplicativos a partir dessas cores e trata Lua e certas configurações de terminal como conteúdo executável. **Recomendação:** transportar primeiro os dados visuais; incorporar comandos e automação somente após revisar suas dependências. [Formato de temas](https://github.com/omacom/omarchy/blob/quattro/manual/43-making-your-own-theme.md).

## Sequência recomendada — decisão de engenharia

1. Manter o rootfs Debian usado pelo port do aparelho como referência; validar compositor, aceleração, entrada, orientação e escala antes de adicionar Omarchy.
2. Aplicar uma paleta e fundo, terminal e poucos atalhos compatíveis com a versão instalada. Manter uma sessão gráfica simples disponível para recuperação.
3. Avaliar Hyprland e componentes Omarchy individualmente; registrar versões e dependências. Não ativar atualização automática, migrações, troca de kernel, configuração de boot ou factory reset do Omarchy.
4. Só depois preparar um rootfs Arch Linux ARM separado e reproduzível, mantendo o boot específico do aparelho. Resolver e testar os pacotes ARM antes de substituir a referência Debian.
5. Considerar o desktop aprovado somente após login repetível, renderização acelerada comprovada e teste de entrada, rotação, suspensão/retorno e consumo. Uma sessão funcional não valida telefonia, câmera, áudio ou segurança de carga.

## Limites da consulta

Foram lidos fontes e documentação oficiais; não houve instalação, compilação, execução de scripts upstream ou teste no aparelho. A branch exibida foi `quattro`. Os links acima são **mutáveis**, não permalinks de commit: o histórico servido pela ferramenta estava em cache e não permitiu estabelecer um SHA atual confiável. Antes da implementação, fixar os commits de `omarchy` e `omarchy-iso`, registrar versões dos pacotes e revalidar estas conclusões. Não foi comprovada compatibilidade integral de nenhum conjunto de pacotes Omarchy com o Exynos 990.
