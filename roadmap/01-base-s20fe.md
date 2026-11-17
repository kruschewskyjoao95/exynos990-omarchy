# Base técnica do S20 FE

Consulta: 16/11/2026. Fontes primárias, leitura de documentação e scripts; nenhum teste local do hardware. Links `main` são mutáveis. SHA atual do repositório não confirmado nesta consulta; fixá-lo antes de compilar.

## O que o autor relata

| Recurso | Estado publicado |
| --- | --- |
| Boot, UFS, tela, toque | Funcionando |
| OpenGL / Panfrost | Funcionando; Vulkan experimental |
| Wi-Fi e USB host/gadget | Funcionando, com ressalvas de reconexão |
| CPU, térmica e carga | Funcionando |
| Bateria e suspensão | Parciais; deep sleep não retorna |
| Áudio interno e Bluetooth | Não funcionando |
| Modem, câmeras e outros periféricos | Sem suporte |

A base publicada usa Debian trixie ARM64. Esse quadro descreve os testes do autor, não a validação do nosso aparelho. [STATUS.md](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/STATUS.md).

## Dependências de construção

O guia identifica kernel `6.12.0-rc5`, base `75138397b8f856193bf344a21a1e1e98179f0901`, e uniLoader `2418e06`. As referências servem para reproduzir o experimento; não são uma avaliação de atualização ou segurança. O DTB e os módulos precisam acompanhar o kernel compilado. [BUILDING.md](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md).

O projeto exige firmware Wi-Fi e o DTB extraído do boot stock do próprio aparelho. Guardar os arquivos localmente, com origem e hash; revisar permissão de redistribuição antes de qualquer release. [FIRMWARE.md](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/FIRMWARE.md).

## Pontos a revisar antes de executar scripts

1. **Host Linux:** `flash-boot.sh` usa `stat -f%z`, sintaxe típica do BSD/macOS, além de `shasum`. Revisar portabilidade para GNU/Linux e testar em arquivos fictícios. Não alterar o script de escrita sem preservar validação e verificação de leitura. [Código](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/flash-boot.sh).
2. **Privilégios no Android:** o mesmo script exige que `adb shell id -u` retorne zero. Depuração USB habilitada não comprova esse acesso; inventariar a ROM antes de escolher o método. [Código](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/flash-boot.sh).
3. **Instalação do desktop:** `build-ufs-image.sh` gera por padrão uma imagem de 700 MB para um buffer de 768 MB e usa `/dev/sda32` na expansão. Conferir layout e limites reais; instalar pacotes grandes depois do boot ou validar outro transporte. [Código](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/build-ufs-image.sh).
4. **Acesso de diagnóstico:** `build-rootfs.sh` configura login root, shell serial e senha SSH para desenvolvimento. Definir uma política de acesso antes de usar em redes compartilhadas ou distribuir imagens. [Código](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/tools/build-rootfs.sh).

Esses pontos são achados de leitura, não uma auditoria completa. Ainda faltam executar builds, revisar todas as ferramentas de escrita e testar a restauração.

## Onde entra o LineageOS

A proposta inicial mantém a cadeia já documentada pelo port. Trocar apenas a imagem de boot pela do LineageOS não constitui uma integração de kernel, DTB, módulos e userspace; seria outra hipótese técnica a desenvolver e testar.

Código de uma ROM Android pode servir como referência de hardware, mas seu aproveitamento exige revisão da interface e das dependências. Nesta etapa, não planejar uma mistura direta de drivers Android com o kernel do port. A decisão é reduzir variáveis e reproduzir primeiro o caminho existente. [Boot descrito pelo autor](https://github.com/bshbsh404/galaxy-s20fe-mainline-linux/blob/main/docs/BUILDING.md).

O reaproveitamento também pode envolver código e serviços, além de referência: há uma rota alternativa de compatibilidade Android. A comparação e os critérios para investigá-la estão no [mapa de integração](04-mapa-de-integracao.md).
