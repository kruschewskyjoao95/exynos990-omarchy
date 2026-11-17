# Roadmap de implementação

Data: 17/11/2026. Alvo: SM-G780F / r8s. M0 parcialmente concluído (inventário e stock `ZTO` verificados; backup de `efs`/`sec_efs` pendente sem `adb root`); artefatos de M1 compilados e verificados no computador ([m1-artifacts.md](../manifests/m1-artifacts.md)); receitas offline de M4 preparadas ([packages-aarch64.md](../manifests/packages-aarch64.md)); **M2 em diante no telefone pendentes**. A pesquisa inicial segue sujeita à validação no hardware.

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

**Decisão do proprietário (17/11/2026): sem rootfs Debian completo.** O kernel do port serve às duas bases; só o rootfs muda. Sequência:

1. **Computador, em paralelo:** kernel/DTB/módulos, lk3rd, uniLoader, initramfs slim (Debian) e rootfs Arch ARM mínimo (≤ 700 MiB, cabe no buffer de 768 MiB do lk3rd).
2. **Teste em RAM** (`fastboot boot`, nada gravado): tela, toque e console USB com o initramfs slim. Confirma o kernel isoladamente.
3. **Gravar o Arch mínimo** em `userdata`; o primeiro boot expande a partição (`r8s-growroot`).
4. **Instalar o Omarchy via `pacman`** sobre o Arch comprovado. O desktop (~1,4 GiB instalado, ver [pacotes](../manifests/packages-aarch64.md)) não cabe na imagem de flash.

Motivo: elimina montar e gravar um Debian que seria descartado, mas mantém um teste que separa falha de kernel de falha de userspace. Se o passo 3 falhar com o passo 2 aprovado, aí sim montar o rootfs Debian do port para isolar a causa.

Fontes e receitas de M1 podem avançar enquanto M0 depende do aparelho. A análise de pacotes de M4 e de drivers de M6 também pode começar cedo; isso não equivale a aprovar seus testes no telefone. Critérios detalhados: V0–V9 em [08](08-contratos-e-validacao.md).

## M0 — Inventário e recuperação

- [x] Registrar Android/ROM atual, versão do bootloader, armazenamento, estado de desbloqueio, acesso a recovery/Download e disponibilidade de root. Modelo já confirmado; não presumir os demais itens. Evidência: [inventário](03-primeira-sessao.md#inventário-atualizado-em-17112026), 17/11/2026 (LineageOS 24.0, bootloader `G780FXXSOFYJ2` desbloqueado, sem `adb root`).
- [ ] Copiar dados pessoais para fora do telefone e verificar amostras restauradas. Inventário registra "sem dados pessoais a preservar"; falta confirmação do proprietário.
- [x] Obter firmware stock correspondente e registrar ferramentas e procedimento de recuperação aplicáveis ao estado atual. Evidência: firmware `G780FXXSOFYJ2` (`ZTO`) via `samloader`, hashes em [sources.md](../manifests/sources.md); Download mode registrado no inventário.
- [x] Obter backups necessários por método compatível com os privilégios disponíveis; registrar tamanhos e SHA-256. Não considerar um backup dentro do telefone suficiente. Evidência: 17/11/2026, 8 partições (inclui `efs`/`sec_efs`/`cpefs`) lidas pelo adb root do LineageOS Recovery, hashes conferidos no aparelho, `backups/stock-backup-verify.txt`. Cópia externa pendente com o proprietário.
- [ ] Inspecionar as fontes de flash e restauração antes de qualquer execução; não usar endereços de partição copiados sem conferir o aparelho. Parcial no computador: `checks/test-flash-tools.sh` (11/11 PASS simulado), `packaging/host-tools/m2-preflight.sh` (leitura de `heimdall`/`fastboot`/`adb`/`samloader` e stock `G780FXXSOFYJ2`) e mapa `/dev/block/by-name/` já inventariado (`boot` → `sda13`, `userdata` → `sda32`); execução real via Download mode (`lk3rd-r8s.tar`) + `fastboot` pendente no aparelho.

**Entrega:** inventário e plano de recuperação. **Aprovação:** artefatos acessíveis no computador e modo de recuperação alcançável. A restauração completa será validada no ciclo de instalação; só entrar nesse ciclo aceitando a perda de dados e efeitos irreversíveis descritos pelo port.

## M1 — Fontes e build reproduzível

- [x] Fixar SHAs do port, kernel, Mesa, lk3rd, uniLoader e Omarchy; guardar procedência e versões das ferramentas. Evidência: [sources.md](../manifests/sources.md), [host-tools.md](../manifests/host-tools.md).
- [x] Reproduzir o build documentado do kernel, lk3rd, uniLoader e initramfs slim; o rootfs Debian completo fica fora (decisão de 17/11/2026). Receitas em `packaging/build-env/`, logs em `logs/m1-*.log`, saídas em `out/boot/`.
- [x] Conferir patches, DTB, firmware, módulos e imagem como um conjunto da mesma compilação. Evidência: 24 patches aplicados sem erro, `kernelrelease=6.12.0-rc5-next-20241104-r8s`, QCA6390 integrado, validado em `out/boot/` por `checks/verify-m1-m4-artifacts.sh`.
- [x] Construir initramfs mínimo para diagnóstico, imagem de boot e rootfs Arch ARM mínimo (≤ 700 MiB, com `r8s-growroot`); registrar tamanho e hash de cada saída. Evidência: [m1-artifacts.md](../manifests/m1-artifacts.md) (`lk3rd-r8s.img` 2097152 B, `r8s-ram.img` 65509376 B ≤ 64 MiB, `r8s-mini.img` 28801024 B ≤ 64 MiB, `r8s-ufs.img` 27785216 B, `initramfs-slim.cpio.gz` 37725548 B, `initramfs-mini.cpio.gz` 1016955 B, `ufs-root.img` 734003200 B / 700 MiB com `e2fsck -fn` ok, módulos `0:0`, `softdog`/pstore/watchdog e 160 pacotes sem kernel genérico). Nada testado no aparelho.
- [ ] Revisar uso de containers privilegiados, dispositivos loop, caminhos fixos, permissões e serviços de diagnóstico. Em revisão (item 5 de `COORDENACAO.md` para serviços Arch/Omarchy e repetição em ambiente limpo).

**Correções de receitas (17/11/2026, codex):** `build-m1-kernel.sh` usa port + `0100` por padrão; `R8S_KERNEL_PATCHSET=series` aplica a lista experimental na ordem e habilita `DEVFREQ_THERMAL`. `0101` permanece fora da lista. O modo `dtbs` foi bloqueado para impedir combinar DTB experimental com kernel anterior. `checks/test-build-recipes.py`: 8 testes locais com compilador/Docker simulados; verificação dos artefatos existentes: 55/55 PASS. Nenhuma imagem foi recompilada nesta correção; a compilação integral da série e a regeneração de initramfs/rootfs continuam pendentes.

**Proteções adicionais (17/11/2026, codex):** o build Arch mantém a imagem/lista de pacotes anteriores até a nova imagem passar por `e2fsck` e limite de tamanho; publica o checksum por último. A limpeza de erro não apaga o chroot que pode continuar com mounts ativos. Flash/restauração ADB exigem identidade `SM-G780F/r8s` e hash do upload antes de escrever; flash rejeita imagem vazia. O instalador Omarchy exige aarch64, DT `samsung,r8s` e Arch ARM antes de alterar configurações. Testes simulados: 11 de build, 18 de flash/restauração, 6 do instalador. Sem acesso ao aparelho e sem reconstruir imagens; V2–V9 continuam pendentes. A publicação dos três arquivos do rootfs não é uma transação atômica: após interrupção durante os renames, exigir checksum válido antes de usar a imagem.

**Entrega:** receita executável revisada e artefatos rastreáveis. **Aprovação:** build completo repetido em ambiente limpo com versões fixadas; registrar diferenças de hash se a construção ainda não for determinística. Referências: [base técnica](01-base-s20fe.md) e [cadeia de artefatos](05-build-e-instalacao.md).

## M2 — Reproduzir o Linux básico no aparelho

**Preparação offline adicional (17/11/2026, codex):** empacotamento agora rejeita kernel/DTB/módulos com hash divergente e slim sem registro de procedência ou de outro build, mesmo com release igual. O slim deve ser regenerado pela receita para produzir `initramfs-slim.kernel.sha256`; nenhum registro foi retroativamente criado para os artefatos atuais. Inspeção ELF do pacote Mesa existente encontrou dependência runtime `libSPIRV-Tools.so`; receita corrigida (`pkgrel=2`, `depends=spirv-tools`), pacote `pkgrel=1` ainda precisa ser regenerado. Testes de build: 17/17; instalador: 6/6; flash simulado: 18/18; integridade dos artefatos existentes: 55/55. Isso não conclui o build integral da série nem os testes físicos.

- [ ] Preparar lk3rd pelo procedimento compatível com o estado inventariado em M0.
- [ ] Após essa preparação, testar kernel e initramfs em RAM; confirmar que esse teste não monta armazenamento em escrita. Instalar lk3rd anteriormente já é uma alteração persistente.
- [ ] Recolher logs de boot e testar console de recuperação antes de instalar o rootfs.
- [ ] Instalar o rootfs Arch ARM mínimo em `userdata` apenas no ciclo de instalação planejado; validar o destino real antes da gravação.
- [ ] Registrar cinco boots consecutivos, rede, toque, renderização, alimentação e temperaturas em repouso e durante 30 minutos de carga controlada.
- [ ] Guardar uma imagem conhecida como funcional e testar retorno a ela.

**Entrega:** kernel comprovado em RAM e Arch ARM mínimo comprovado no aparelho. **Aprovação:** boots e recuperação repetíveis, sem travamentos observados no ensaio; carga e temperatura dentro dos limites documentados para o hardware. Esse ensaio não certifica segurança elétrica nem autonomia de uso diário.

## M3 — Gráficos e entrada antes do desktop completo

- [ ] Validar DRM/KMS, Mesa e um compositor Wayland mínimo antes do ambiente completo.
- [ ] Usar um compositor mínimo compatível com a referência para testar a camada gráfica. Validar o conjunto definitivo Hyprland/Omarchy em M4.
- [ ] Comprovar renderer de hardware; não aceitar renderização por software como validação da aceleração.
- [ ] Integrar terminal, navegador ARM64 e interface de rede. Testar escala, toque, orientação manual, teclado virtual e teclado USB.
- [ ] Registrar problemas de orientação, escala e entrada que a sessão final de M4 precisa resolver.

**Entrega:** prova de hardware gráfico e entrada no Arch ARM mínimo. **Aprovação:** renderer de hardware, toque alinhado, terminal e aplicação gráfica utilizáveis, incluindo reinício. Usar periféricos para diagnóstico quando necessário; navegação completa por toque será requisito da sessão final.
## M4 — Base Arch ARM e integração do Omarchy

- [x] Auditar versões e disponibilidade ARM64 de todos os componentes escolhidos; separar essenciais de opcionais. Evidência preliminar de metadados `.db` (`stable/aarch64`): [packages-aarch64.md](../manifests/packages-aarch64.md) e [packages-aarch64-stable.tsv](../manifests/packages-aarch64-stable.tsv) (108 pacotes resolvidos, 1408,1 MiB instalados; 23 deps por soname e instalação real no aparelho ainda pendentes).
- [ ] Comparar receitas e patches dos pacotes Omarchy com os pacotes Arch ARM; nome igual não comprova equivalência. Fixar um conjunto compatível conforme [06](06-pacotes-e-desktop.md).
- [ ] Instalar o Omarchy via `pacman` sobre o Arch ARM mínimo já comprovado (depois do `r8s-growroot`), conservando as imagens recuperáveis. Receita pós-boot `packaging/omarchy/install-omarchy-r8s.sh` (`--dry-run` e `bash -n` ok) aguardando revisão e M2/M3.
- [ ] Integrar suporte r8s, serviços, firmware e Mesa; repetir os ensaios de M2/M3 nessa base antes de adicionar o desktop completo.
  - Receita Arch atualizada em 17/11/2026: inclui `qca/htbtfw20.tlv` e `qca/htnv20.bin` do vendor local, com hashes fixados em `manifests/bluetooth-firmware.sha256` e rejeição de arquivos ausentes/corrompidos antes do build. O `ufs-root.img` existente ainda não contém esses arquivos; regeneração e teste Bluetooth no aparelho pendentes.
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

Manter este diretório como projeto de integração. Na implementação, usar checkouts separados dos upstreams, patches pequenos e versões fixadas; criar forks remotos quando houver mudanças concretas a manter. Em 17/11/2026 há documentos, manifestos (`sources.md`, `host-tools.md`, `packages-aarch64.md`, `m1-artifacts.md`), artefatos M1 compilados em `out/` com verificação automatizada (`checks/test-flash-tools.sh`, `checks/verify-m1-m4-artifacts.sh`, `packaging/host-tools/m2-preflight.sh`), e receita M4 em revisão; nenhum teste foi executado no aparelho. Não duplicar árvores inteiras nem desenvolver drivers novos antes de reproduzir a base.

Dependências dos testes físicos: M0 + M1 → M2 → M3 → M4 → M5. Pesquisa e preparação no computador podem avançar nas frentes independentes. M6 usa a base de teste de M2 ou posterior, sem bloquear a alpha se as limitações forem explícitas. Planejar por resultados medidos; prazo de calendário só depois de M2.
