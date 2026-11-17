# linuxs20fe

Roadmap para um Linux nativo no **Samsung Galaxy S20 FE SM-G780F, Exynos 990, r8s**, com uma adaptação do ambiente Omarchy. Modelo confirmado pelo proprietário em 16/11/2026.

**Estado: roadmap de execução e pesquisa de fontes; nenhuma imagem foi compilada ou instalada por este projeto.**

## Como vamos fazer

1. Reproduzir a base do [port do S20 FE](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux), mantendo seu boot, kernel, device tree e firmware.
2. Validar o Debian ARM64 usado pelo port como referência de hardware, com uma sessão gráfica mínima.
3. Preparar um rootfs Arch Linux ARM separado e integrar componentes compatíveis do Omarchy, preservando o suporte Samsung.
4. Empacotar o resultado como uma distribuição derivada experimental, com atualização controlada e recuperação testada.

**O resultado pretendido é Arch ARM com o ambiente real do Omarchy, usando o suporte de hardware do port r8s.** O Debian é uma referência temporária; não precisamos portar todo o Omarchy para Debian. LineageOS entra como fonte de código e investigação dos recursos ausentes, não como um segundo sistema que precisa iniciar junto.

```text
Boot Samsung → lk3rd → uniLoader → kernel + DTB do S20 FE
                                      ↓
                         rootfs ARM64 + serviços do aparelho
                                      ↓
                            Mesa + compositor Wayland
                                      ↓
                         ambiente Omarchy adaptado ao toque
```

A cadeia de boot vem do [guia do port](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/FLASHING.md); as camadas de integração acima são a proposta deste projeto.

## Por onde começar

Agentes devem ler [AGENTS.md](AGENTS.md), depois o mapa e o roadmap. Cada etapa aponta para o guia técnico correspondente. Os contratos definem o que conta como entrega concluída.

| Documento | Quando consultar |
| --- | --- |
| [Mapa da integração](roadmap/04-mapa-de-integracao.md) | Entender como as peças formam um único sistema |
| [Roadmap de execução](roadmap/00-roadmap.md) | Escolher a próxima tarefa e verificar dependências |
| [Build e instalação](roadmap/05-build-e-instalacao.md) | Produzir imagens, preparar boot e instalar no armazenamento |
| [Pacotes e desktop](roadmap/06-pacotes-e-desktop.md) | Construir a base Arch e integrar o Omarchy |
| [LineageOS e drivers](roadmap/07-lineage-e-drivers.md) | Investigar áudio, modem, câmeras e outros recursos |
| [Contratos e validação](roadmap/08-contratos-e-validacao.md) | Registrar versões, comprovar integração e aceitar uma entrega |

Referências complementares:

- [Base técnica e limitações do aparelho](roadmap/01-base-s20fe.md)
- [Pesquisa de compatibilidade Omarchy/ARM64](roadmap/02-omarchy-arm64.md)
- [Primeira sessão prática: inventário e preparação](roadmap/03-primeira-sessao.md)

**Próxima ação de implementação:** fixar fontes e produzir a receita reproduzível de M1. Em paralelo, preencher o inventário M0 quando o aparelho estiver acessível. O MVP é um computador portátil com Omarchy, Wi-Fi, terminal e navegador; substituir todas as funções de um telefone depende dos recursos de M6.

Os relatos dos autores não são testes feitos neste aparelho. Desbloqueio e gravação podem apagar dados, alterar permanentemente o estado Knox e inutilizar o dispositivo; a implementação exige backups externos e um caminho de restauração verificado. [Riscos documentados pelo port](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/FLASHING.md).
