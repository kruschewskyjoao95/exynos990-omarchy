# Cópia externa verificada — 17/11/2026

- Destino: HD USB Hitachi de 298 GiB, volume exFAT `Dados`, montado em `/run/media/joao/Dados` (disco diferente do NVMe interno).
- Pasta nova: `/run/media/joao/Dados/S20FE-backup-2026-11-17-vsflonnh/backups/`.
- Copiados todos os **23 arquivos** de `backups/`, **400.893.292 bytes**, sem sobrescrever arquivos existentes do HD. Originais preservados.
- Gerado `full-backup.sha256` na pasta externa, incluindo hashes dos 23 arquivos. Dados sincronizados no filesystem; todos os arquivos da cópia foram relidos e comparados por SHA-256 com os originais.
- `sha256sum -c backup-manifest.sha256` executado dentro da cópia: **10/10 OK**.
- Proprietário confirmou: celular formatado ontem, sem dados pessoais a preservar.
- Recovery conectado: ADB root (`uid=0`), modelo `SM-G780F`, device `r8s`, verified boot `orange`, bateria **100%**. Leituras delimitadas, sem varredura de atributos da bateria.
- `boot` → `sda13` (120.832 setores, 61.865.984 bytes), `recovery` → `sda14`, `userdata` → `sda32` (227.057.664 setores, 116.253.523.968 bytes).
- Hashes atuais de boot/recovery/dtbo lidos no aparelho iguais aos backups locais `stock-*` e à cópia externa. Identificadores pessoais omitidos.

Esta evidência comprova cópia/integridade; a restauração no aparelho ainda não foi ensaiada. O volume exFAT não reproduz permissões POSIX, mas preservou o conteúdo binário de todos os arquivos.
