# Roadmap de implementação

Data: 16/11/2026. Alvo: SM-G780F / r8s. Todas as etapas de implementação estão **pendentes**. A pesquisa inicial está concluída, sujeita à revalidação ao fixar commits.

## Entrega pretendida

Construir uma distribuição derivada experimental: suporte ao aparelho vindo do port r8s, base ARM64 e ambiente Omarchy adaptado. A primeira entrega utilizável deve abrir terminal e navegador, acessar Wi-Fi, aceitar toque e permitir recuperação pelo computador.

As metas de teste abaixo são critérios propostos para este projeto, não garantias dos upstreams. Avançar quando a etapa anterior produzir evidências; registrar falhas e logs em vez de marcar funcionamento por inferência.

**Escopo do planejamento:** este roadmap cobre a sequência até a alpha e a investigação de funções de telefone. O [mapa de integração](04-mapa-de-integracao.md) define a arquitetura; [05](05-build-e-instalacao.md) detalha artefatos e instalação; [06](06-pacotes-e-desktop.md) mapeia pacotes e integração; [07](07-lineage-e-drivers.md) rastreia os recursos Android; [08](08-contratos-e-validacao.md) define contratos e testes. Suporte r8s já existente será reaproveitado.

## Ordem de execução e entregas

| Marco | Entrada necessária | Entrega verificável |
| --- | --- | --- |
| M0 | Aparelho e acesso do proprietário | Inventário + backups + caminho de recuperação |
| M1 | Fontes, ferramentas e firmware necessário | Manifesto, receita e imagens de referência |
| M2 | M0 + M1 | Boot e recuperação comprovados no telefone |
| M3 | M2 | Gráficos e entrada comprovados com sessão mínima |
| M4 | Base validada + pacotes resolvidos | Arch ARM com shell e ferramentas Omarchy |
| M5 | M4 | Alpha instalável, atualização e retorno testados |
| M6 | Recurso escolhido + base de teste | Função móvel adicional demonstrada em aplicativo real |

Fontes e receitas de M1 podem avançar enquanto M0 depende do aparelho. A análise de pacotes de M4 e de drivers de M6 também pode começar cedo; isso não equivale a aprovar seus testes no telefone. Critérios detalhados: V0–V9 em [08](08-contratos-e-validacao.md).

## M0 — Inventário e recuperação

- [ ] Registrar Android/ROM atual, versão do bootloader, armazenamento, estado de desbloqueio, acesso a recovery/Download e disponibilidade de root. Modelo já confirmado; não presumir os demais itens.
- [ ] Copiar dados pessoais para fora do telefone e verificar amostras restauradas.
- [ ] Obter firmware stock correspondente e registrar ferramentas e procedimento de recuperação aplicáveis ao estado atual.
- [ ] Obter backups necessários por método compatível com os privilégios disponíveis; registrar tamanhos e SHA-256. Não considerar um backup dentro do telefone suficiente.
- [ ] Inspecionar as fontes de flash e restauração antes de qualquer execução; não usar endereços de partição copiados sem conferir o aparelho.

**Entrega:** inventário e plano de recuperação. **Aprovação:** artefatos acessíveis no computador e modo de recuperação alcançável. A restauração completa será validada no ciclo de instalação; só entrar nesse ciclo aceitando a perda de dados e efeitos irreversíveis descritos pelo port.

## M1 — Fontes e build reproduzível

- [ ] Fixar SHAs do port, kernel, Mesa, lk3rd, uniLoader e Omarchy; guardar procedência e versões das ferramentas.
- [ ] Reproduzir primeiro o build Debian ARM64 documentado; revisar os scripts para o Linux do computador e separar diretórios de saída dos discos reais.
- [ ] Conferir patches, DTB, firmware, módulos e imagem como um conjunto da mesma compilação.
- [ ] Construir initramfs mínimo para diagnóstico, imagem de boot e rootfs básico; registrar tamanho e hash de cada saída.
- [ ] Revisar uso de containers privilegiados, dispositivos loop, caminhos fixos, permissões e serviços de diagnóstico.

**Entrega:** receita executável revisada e artefatos rastreáveis. **Aprovação:** build completo repetido em ambiente limpo com versões fixadas; registrar diferenças de hash se a construção ainda não for determinística. Referências: [base técnica](01-base-s20fe.md) e [cadeia de artefatos](05-build-e-instalacao.md).

## M2 — Reproduzir o Linux básico no aparelho

- [ ] Preparar lk3rd pelo procedimento compatível com o estado inventariado em M0.
- [ ] Após essa preparação, testar kernel e initramfs em RAM; confirmar que esse teste não monta armazenamento em escrita. Instalar lk3rd anteriormente já é uma alteração persistente.
- [ ] Recolher logs de boot e testar console de recuperação antes de instalar o rootfs.
- [ ] Instalar a base mínima em armazenamento apenas no ciclo de instalação planejado; validar o destino real antes da gravação.
- [ ] Registrar cinco boots consecutivos, rede, toque, renderização, alimentação e temperaturas em repouso e durante 30 minutos de carga controlada.
- [ ] Guardar uma imagem conhecida como funcional e testar retorno a ela.

**Entrega:** Debian básico comprovado no aparelho. **Aprovação:** boots e recuperação repetíveis, sem travamentos observados no ensaio; carga e temperatura dentro dos limites documentados para o hardware. Esse ensaio não certifica segurança elétrica nem autonomia de uso diário.

## M3 — Gráficos e entrada antes do desktop completo

- [ ] Validar DRM/KMS, Mesa e um compositor Wayland mínimo antes do ambiente completo.
- [ ] Usar um compositor mínimo compatível com a referência para testar a camada gráfica. Validar o conjunto definitivo Hyprland/Omarchy em M4.
- [ ] Comprovar renderer de hardware; não aceitar renderização por software como validação da aceleração.
- [ ] Integrar terminal, navegador ARM64 e interface de rede. Testar escala, toque, orientação manual, teclado virtual e teclado USB.
- [ ] Registrar problemas de orientação, escala e entrada que a sessão final de M4 precisa resolver.

**Entrega:** prova de hardware gráfico e entrada na referência Debian. **Aprovação:** renderer de hardware, toque alinhado, terminal e aplicação gráfica utilizáveis, incluindo reinício. Usar periféricos para diagnóstico quando necessário; navegação completa por toque será requisito da sessão final. Não é necessário tematizar Debian nem portar todo o Omarchy para essa base.

## M4 — Base Arch ARM e integração do Omarchy

- [ ] Auditar versões e disponibilidade ARM64 de todos os componentes escolhidos; separar essenciais de opcionais.
- [ ] Comparar receitas e patches dos pacotes Omarchy com os pacotes Arch ARM; nome igual não comprova equivalência. Fixar um conjunto compatível conforme [06](06-pacotes-e-desktop.md).
- [ ] Construir rootfs Arch Linux ARM separado, conservando a referência Debian e as imagens recuperáveis.
- [ ] Integrar suporte r8s, serviços, firmware e Mesa; repetir os ensaios de M2/M3 nessa base antes de adicionar o desktop completo.
- [ ] Portar o conjunto coerente de compositor, shell, temas e comandos do Omarchy para a revisão escolhida. Resolver dependências entre configurações, pacotes e caminhos.
- [ ] Adaptar comandos de energia, rede, brilho e sessão ao telefone; manter fora da imagem os componentes incompatíveis, com justificativa explícita.
- [ ] Integrar teclado virtual e controles por toque; completar o fluxo Wi-Fi → launcher → navegador → digitação → terminal → alternância de apps → desligamento.
- [ ] Revisar instalador, atualização, migrações e ações de restauração para não substituir o boot/kernel Samsung nem aplicar pressupostos de disco de PC.

**Entrega:** ambiente Omarchy adaptado sobre Arch ARM. **Aprovação:** V4–V6, login repetível e atualização experimental de um componente com retorno à versão anterior. O shell e os comandos escolhidos precisam funcionar; papel de parede não satisfaz essa entrega. Ver [pacotes e desktop](06-pacotes-e-desktop.md).

## M5 — Imagem alpha distribuível

- [ ] Automatizar o build já validado, com manifesto de fontes, licenças, pacotes e hashes.
- [ ] Separar a imagem inicial pequena dos pacotes de desktop instalados depois, ou validar um transporte alternativo para imagens maiores. Não presumir que o desktop cabe no método de flash do port.
- [ ] Criar usuário comum, autenticação de recuperação definida e SSH por chave; revisar autologin e shells root de diagnóstico antes de distribuir.
- [ ] Definir política de correções de segurança para o kernel customizado; não substituí-lo por kernel genérico durante atualizações.
- [ ] Implementar e testar a integração do ciclo de atualização/boot para r8s; sucesso de um comando genérico sem ação no boot não comprova atualização do aparelho.
- [ ] Testar instalação limpa, reinício, atualização e retorno à versão funcional, incluindo falha da sessão gráfica.
- [ ] Documentar funções ausentes e separar blobs locais dos arquivos redistribuíveis; revisar as licenças de cada componente.

**Entrega:** alpha versionada, guia de instalação/restauração e resultados de teste. **Aprovação:** repetir o processo a partir dos artefatos publicados, com dados de teste, no aparelho alvo. Restauração da ROM não desfaz alterações irreversíveis de Knox.

## M6 — Autonomia e funções de telefone

Tratar como pesquisas independentes: áudio, Bluetooth, suspensão/retorno, consumo, modem, câmeras e sensores. Priorizar energia e áudio após a alpha. Cada recurso exige evidência própria de driver, firmware e integração com o userspace; temas e troca de distribuição não o implementam.

- [ ] Para cada função ausente, mapear a implementação correspondente no kernel e na árvore de dispositivo do LineageOS, incluindo serviços e dependências proprietárias.
- [ ] Classificar o aproveitamento: código portável para o kernel do projeto, informação de hardware/firmware, ou serviço Android que exige compatibilidade adicional.
- [ ] Fazer uma prova isolada do recurso antes de incorporá-lo à imagem principal; verificar também regressões no suporte já funcional.
- [ ] Se optar por kernel Android e adaptação Halium/libhybris, tratar como uma base alternativa e revalidar boot, gráficos e desktop. Não pressupor que os resultados da base mainline continuam válidos.

**Critério para chamar de telefone de uso diário:** requisitos definidos com o proprietário e testes reais de chamadas, microfone/alto-falante, conectividade e autonomia, além de estabilidade. Até lá, apresentar como computador portátil experimental. Sem prazo prometido para drivers ausentes.

Rastreamento inicial de arquivos e provas por recurso: [LineageOS e drivers](07-lineage-e-drivers.md).

## Organização do trabalho

Manter este diretório como projeto de integração. Na implementação, usar checkouts separados dos upstreams, patches pequenos e versões fixadas; criar forks remotos quando houver mudanças concretas a manter. Hoje só existem documentos. Não duplicar árvores inteiras nem desenvolver drivers novos antes de reproduzir a base.

Dependências dos testes físicos: M0 + M1 → M2 → M3 → M4 → M5. Pesquisa e preparação no computador podem avançar nas frentes independentes. M6 usa a base de teste de M2 ou posterior, sem bloquear a alpha se as limitações forem explícitas. Planejar por resultados medidos; prazo de calendário só depois de M2.
