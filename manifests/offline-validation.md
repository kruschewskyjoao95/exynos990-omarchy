# Validação offline ARM64 — 17/11/2026

Execução real de userspace AArch64 em Docker/QEMU no computador; nenhum acesso ao telefone. Não comprova boot nativo, GPU, tela, toque, consumo ou bloqueio de sessão real.

## Correções e resultados

- `packaging/omarchy/desktop-packages.txt` é a lista única usada pelo instalador e pelo ensaio. A instalação faz atualização e inclusão do desktop em uma transação `pacman -Syu`; ao copiar o instalador para o telefone, copiar também esse arquivo ao lado dele.
- O teste instalou os pacotes com verificação de assinaturas e executou o instalador completo. Apenas a leitura do DT foi redirecionada para uma fixture `samsung,r8s`; nenhuma trava foi removida do instalador de produção. O container executou AArch64 e verificou a identidade Arch ARM de `/usr/lib/os-release`.
- O pacote `omarchy-settings 4.5.0-3` sobrescreve `/etc/os-release`; consultar esse arquivo impedia repetir a instalação. Corrigido para consultar a identificação da distribuição base em `/usr/lib/os-release`.
- O hook `00-omarchy-update-guard.hook` recusa `pacman -Syu` direto quando Omarchy já está presente. O bootstrap agora passa `OMARCHY_ALLOW_DIRECT_PACMAN=1` apenas à sua própria transação. O hook permanece ativo para os demais comandos; isso não valida o fluxo futuro de atualizações/migrações.
- O botão de energia chamava `omarchy-lock-screen`, ausente dos pacotes. Agora chama `omarchy-system-lock` antes do DPMS. Teste simulado verifica a ordem; funcionamento e autenticação do lock dependem da sessão real.
- Mesa revisão 2 instalado; `ldd` de EGL e PanVK sem `not found`. `spirv-tools` consta nas dependências. As sete bibliotecas ELF têm hashes iguais aos da revisão 1; foi reempacotada a compilação existente usando `makepkg --repackage --nodeps`, sem nova compilação. As dependências runtime foram verificadas no ensaio de instalação posterior.
- `systemd-analyze verify --man=no` aprovou as unidades r8s geradas e SDDM. Isso verifica estrutura, referências e executáveis, não a execução dos serviços no hardware.
- Instalação final: **470 pacotes**, incluindo Mesa customizado, registrados em [arm64-validated-packages.txt](arm64-validated-packages.txt). Nenhum kernel genérico, Limine ou mkinitcpio instalado; `linux-api-headers` é a exceção permitida.

## Reprodução e artefatos

Com Docker e emulação ARM64 disponíveis, executar `bash checks/validate-arm64-userspace.sh`. A receita exige o pacote Mesa revisão 2 em `out/packages/`. Usa o ID local da imagem `r8s-alarm-builder:latest`, registrado em `out/validation/arm64/builder-image.txt`, projeto somente leitura, sem dispositivos ou modo privilegiado. O container termina e fica guardado para inspeção; cache de pacotes/assinaturas, configs e logs ficam em `out/validation/arm64/` e `logs/codex-arm64-userspace.log`.

- Builder usado: `sha256:76b124459d9dc35056b250d428f5a0cbdfbf098f794144eba1fd4322c35dfe4d`.
- Snapshot local após instalar: `r8s-userspace-validated:20261117`, `sha256:2afdcf2eb997ed1acb88e25649beec23e89e66c2af07399d5415801f36ac8e47`.
- Pacote `out/packages/mesa-g77-26.3.0_devel.7d6bb09d-2-aarch64.pkg.tar.xz`: 5.823.604 bytes, SHA-256 `4a62c5a3275d22675457476fec0cb66bc0f19a83adb184b9741fc8e3fc8eae44`.
- Cache de pacotes e assinaturas preservado em `out/validation/arm64/pkgcache/`; o manifesto de versões não substitui esse cache e o snapshot local para reprodução. Os repositórios continuam mutáveis.

## Boot e limites

Slim regenerado pela receita, com `initramfs-slim.kernel.sha256` produzido durante o build. Imagens RAM/UFS/mini reempacotadas e inspecionadas; hashes/tamanhos atuais em [m1-artifacts.md](m1-artifacts.md). `r8s-ram.img` = **65.513.472 bytes**, abaixo dos 67.108.864 bytes do loader. Artefatos anteriores preservados em `out/validation/baseline/`. Rootfs Arch existente não foi alterado: firmware Bluetooth novo e novos patches de kernel ainda precisam entrar em uma reconstrução própria.

Regressão: **17 testes de build + 10 de instalador + 18 de flash simulado** passaram. Verificação de artefatos: **56 PASS, 0 FAIL**.

`Hyprland --verify-config` no snapshot apresentou inicialmente erro Lua por ausência de `HYPRLAND_INSTANCE_SIGNATURE`. Com assinatura simulada, não surgiu novo erro no trecho observado, mas o processo não encerrou; ambos os containers de checagem foram interrompidos. Não registrar essa tentativa como aprovação da configuração ou da sessão. O ensaio de instalação acima concluiu normalmente e permanece separado desse limite.
