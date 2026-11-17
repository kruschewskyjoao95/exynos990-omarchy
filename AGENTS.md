# linuxs20fe: entrada para agentes

Objetivo: instalar um sistema nativo derivado do Omarchy no Samsung **SM-G780F / Exynos 990 / r8s**. Modelo confirmado pelo usuário. O projeto está na fase de documentação; verifique os artefatos existentes antes de relatar progresso.

## Antes de trabalhar

1. Leia [o mapa de integração](roadmap/04-mapa-de-integracao.md) para entender as camadas e a rota escolhida.
2. Leia [o roadmap](roadmap/00-roadmap.md) e escolha a primeira tarefa sem evidência de conclusão que não dependa de um bloqueio externo.
3. Para build, boot, rootfs ou flash, leia [a sequência de instalação](roadmap/05-build-e-instalacao.md). Para pacotes, compositor ou Omarchy, leia [o plano de desktop](roadmap/06-pacotes-e-desktop.md). Para funções ausentes ou proposta de usar LineageOS, leia [a investigação de drivers](roadmap/07-lineage-e-drivers.md).
4. Antes de marcar uma entrega concluída, aplique [os contratos e testes](roadmap/08-contratos-e-validacao.md).

## Decisões da implementação

- Rota principal: boot/kernel/DTB/Mesa do port r8s + rootfs Arch Linux ARM + ambiente real do Omarchy adaptado. Há um kernel em execução; dependências e módulos pertencem à compilação selecionada.
- Debian é a referência temporária para reproduzir o port. A entrega final inclui shell, comandos e sessão do Omarchy; apenas copiar temas não conclui o objetivo.
- LineageOS é fonte de implementação e investigação por recurso. Uma base Android com Halium/libhybris é uma rota alternativa, com validação própria; não é uma etapa obrigatória da rota principal.
- Construa o sistema em diretório de staging/ambiente isolado. O Omarchy instalado no computador é referência de leitura, não o destino do trabalho.
- Preserve o boot Samsung e os drivers já funcionais ao integrar o userspace. A ISO e o particionamento para computadores não são o mecanismo escolhido para o telefone.
- Documente fonte/commit e diferencie: observado no código, relatado pelo autor, proposta nossa e testado neste aparelho. URL de branch não é versão fixada.
- Desenvolva fontes, receitas e verificações sem depender da conexão do aparelho quando possível. Escritas no telefone dependem do pedido vigente, identificação do alvo, backups e artefatos verificados; este roadmap não constitui uma ordem de flash.

## Trabalho com mais de um agente

Mais de um agente trabalha neste diretório (Gemini/Antigravity e Claude Code). O quadro comum é [COORDENACAO.md](COORDENACAO.md); o histórico é o git.

1. Ao iniciar, leia `COORDENACAO.md` e `git log --oneline -10`.
2. Antes de alterar arquivos, registre em "Em andamento": agente, tarefa e caminhos. Não altere caminhos que outro agente registrou.
3. Ao terminar uma tarefa, faça um commit pequeno com mensagem descritiva e mova o item para "Feito, aguardando revisão" com o SHA.
4. Ao revisar, anote o problema em "Revisão" com arquivo e ação esperada. Não corrija o trabalho do outro agente; o autor corrige e marca `[x]`.
5. Escritas no telefone (flash, unlock, restore) só com ordem explícita do proprietário. Combinação entre agentes não autoriza.

## Evidência de progresso

Atualize a etapa correspondente com artefatos e resultados. Se faltar acesso à rede ou ao dispositivo, registre o bloqueio exato e prossiga nas tarefas independentes. Uma falha de obtenção de fonte não comprova ausência de suporte. Não reporte instalação, teste ou compatibilidade com base apenas em documentação de terceiros.
