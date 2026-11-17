# Contratos entre componentes e validação

Este documento define entregas propostas para a implementação. Os diretórios e nomes abaixo ainda não são artefatos existentes. Use os caminhos já adotados pelos upstreams nos builds e registre a correspondência; não duplique ferramentas apenas para obter estes nomes.

## Fronteiras do sistema

| Fronteira | Entrada | Saída/contrato | Como comprovar |
| --- | --- | --- | --- |
| Computador → build | Fontes fixadas, ferramentas, firmware autorizado | Binários AArch64 e manifesto | Registrar arquitetura ELF, versões, hashes e logs de build |
| Boot → kernel | Imagem no formato aceito pela cadeia r8s | Kernel + DTB + cmdline coerentes | Extrair a imagem construída e conferir seus componentes; coletar log de boot |
| Kernel → rootfs | Drivers necessários para montar raiz, caminho de root correto | `/sbin/init` e bibliotecas ARM64 executáveis | Boot real até systemd; simulação não valida o hardware |
| Kernel → módulos | Uma única versão/configuração de build | Árvore de módulos correspondente | Conferir `uname -r`, módulos carregados e erros no log |
| Kernel → Mesa | Dispositivos DRM/render e permissões | EGL/OpenGL de hardware | Testar contexto gráfico e renderer; registrar falhas DRM/Panfrost |
| Mesa → Hyprland | Bibliotecas e extensões exigidas pela versão escolhida | Compositor estável na tela interna | Abrir sessão, entrada, aplicações e múltiplos reinícios |
| Hyprland → Omarchy | Versões, bootstrap, módulos e dependências coerentes | Shell, launcher, comandos e sessão funcionais | Testar funcionalidades da lista de aceite abaixo |
| Sistema → atualização | Pacotes e conjunto boot/kernel/módulos conhecidos | Nova versão e recuperação definida | Ensaiar atualização e retorno, com logs e hashes |

A fronteira com o armazenamento é descrita em [build e instalação](05-build-e-instalacao.md). A integração de pacotes está em [pacotes e desktop](06-pacotes-e-desktop.md). Estes contratos são requisitos nossos, não resultados medidos.

## Manifesto de fontes e pacotes

Na primeira implementação, produzir um único manifesto versionado com os campos abaixo. `PENDENTE` é um bloqueio de reprodutibilidade, nunca um valor que o build deve aceitar silenciosamente.

| Registro | Campos obrigatórios |
| --- | --- |
| Fontes | URL, commit completo, patches locais ordenados, licença e data de obtenção |
| Kernel | Fonte/base, configuração, versão resultante, DTB e hash de cada saída |
| Firmware | Nome, origem, hash e condição de redistribuição; arquivos privados ficam fora do Git |
| Ferramentas | Ambiente/arquitetura, compilador, empacotador de boot e versões |
| Pacotes | Nome, arquitetura, versão, repositório/canal, assinatura validada e cópia ou origem recuperável |
| Imagens | Hash, tamanho, conteúdo, destino lógico e combinação de kernel/módulos/rootfs |
| Teste | Modelo, versão instalada, procedimento, resultado, log e data |

Rastrear pelo menos: port r8s, árvore base do kernel, Mesa, lk3rd, uniLoader, ferramenta de boot AOSP, Omarchy e o conjunto de pacotes ARM. Referências LineageOS entram se forem usadas numa prova de recurso. Guardar o conjunto de pacotes resolvido; listar versões de um repositório rolling sem preservar uma forma de recuperá-las não permite reconstrução posterior.

## Organização mínima proposta

```text
linuxs20fe/
  AGENTS.md + README.md + roadmap/     orientação existente
  sources/                            checkouts identificados, quando obtidos
  packaging/                          receitas e alterações locais necessárias
  manifests/                          fontes, pacotes, imagens e hashes
  out/                                artefatos gerados, fora do controle de versão
  checks/                             resultados de testes sanitizados
```

Backups pessoais e de partições ficam em armazenamento externo ao repositório. Antes de criar arquivos gerados ou obter fontes, configurar as exclusões de Git correspondentes. Criar apenas diretórios utilizados pela tarefa em execução.

## Testes de aceite por etapa

| ID | Teste | Critério para passar |
| --- | --- | --- |
| V0 | Identidade e recuperação | SM-G780F confirmado, modos acessíveis, backups externos legíveis e plano de restauração correspondente |
| V1 | Build | Receita termina sem erros, manifesto completo, arquitetura e componentes das imagens conferidos |
| V2 | Diagnóstico em RAM | Initramfs real abre console; armazenamento do usuário não é montado em escrita pelo teste |
| V3 | Sistema mínimo | Cinco boots completos; rede e console de recuperação funcionam; retorno à imagem conhecida comprovado |
| V4 | Gráficos | Renderer de hardware, toque alinhado e terminal/navegador utilizáveis; logs sem erros gráficos recorrentes no ensaio |
| V5 | Desktop Omarchy | Sessão, shell, launcher, tema, terminal e comandos escolhidos funcionam com a matriz de pacotes registrada |
| V6 | Uso móvel | Abrir, alternar e fechar apps; digitar, conectar Wi-Fi, ajustar brilho e desligar pelos controles disponíveis |
| V7 | Energia | Registrar carga, temperaturas, consumo e retorno da suspensão quando habilitada; limites documentados, falhas declaradas |
| V8 | Instalação/atualização | Repetir instalação a partir de artefatos e testar retorno após atualização; preservar acesso de recuperação |
| V9 | Recurso adicional | Aplicação real usa o recurso investigado e os testes essenciais anteriores continuam passando |

Para V6, o teclado virtual deve ser testado no terminal e no navegador reais; pacote instalado ou teclado visível não comprova que a entrada chega aos aplicativos. Para V7, uma função de suspensão desabilitada pode permitir uma alpha, desde que a limitação esteja explícita; não marcar suspensão como funcionando.

## O que conta como instalação do Omarchy no S20 FE

Aceitar como primeira instalação funcional quando: boot autônomo até Arch ARM; kernel e suporte r8s preservados; sessão Hyprland com shell e ferramentas Omarchy selecionadas; navegação por toque; rede, terminal e navegador; manifesto e recuperação. A lista de comandos incluídos/excluídos deve acompanhar a imagem. A referência Debian tematizada é uma entrega intermediária.

Audio interno, chamadas, câmeras e autonomia de telefone cotidiano são requisitos da etapa de funções móveis, não evidências implícitas de V5. Uma alpha sem eles deve declarar essas ausências.

## Atualização e manutenção

Planejar atualização do userspace e atualização do conjunto de boot separadamente. Uma alteração de kernel inclui DTB, módulos e imagem compatíveis; não confiar que atualizar um arquivo em `/boot` reconstrói automaticamente a imagem usada por lk3rd. Ensaio e recuperação pertencem à mesma entrega da atualização.

Fixar o ambiente de reprodução e testar atualizações em uma cópia controlada. Ao usar Arch, manter transações coerentes de pacotes/dependências; não conservar indefinidamente bibliotecas antigas com atualizações parciais improvisadas. A estratégia exata de repositório/espelho e empacotamento será implementada com a matriz de [06](06-pacotes-e-desktop.md).

## Bloqueios ainda abertos

1. Inventário do estado atual do aparelho e do acesso disponível.
2. Checkouts fixados e build integral reproduzido localmente.
3. Disponibilidade do conjunto de pacotes no canal escolhido e validação com Mesa/Hyprland.
4. Receita Arch ARM, instalação e atualização testadas no r8s.
5. Viabilidade de cada recurso ainda ausente.

Os itens 2 e parte do 3 podem avançar sem o aparelho. Os demais não devem ser preenchidos por suposição. Este documento define como fechar as lacunas; não afirma que estejam resolvidas.
