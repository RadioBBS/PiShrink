# PiShrink – Changelog

```
PiShrink – Aenderungsverlauf des Projekts.

Projekt:     PiShrink
Modul:       CHANGELOG.md
Version:     1.1.0
Stand:       2026-08-22
Abhaengig:   bash >= 4; Root-Rechte; parted, losetup, tune2fs, md5sum,
             e2fsck, resize2fs; optional gzip/pigz, xz
Bezug:       requirements.txt (kein Python)
Lizenz:      MIT
Upstream:    https://github.com/Drewsif/PiShrink (Drew Bonasera)
Erstellt mit: Cursor Grok 4.6
Autor:       (FFHB) / RadioBBS
```

Format: `Version X.Y.Z – YYYY-MM-DD – Beschreibung` (neueste unten).

## Upstream v26.03.16 – 2026-03-16

- Original PiShrink von Drew Bonasera (Drewsif), MIT-Lizenz.

## Version 1.0.0 – 2026-08-02

- Deutsche Lokalisierung nach Styleguide: Header, `--help`/`--version`,
  Logging mit Zeitstempel, `--Ende`/`-E`, dokumentierte Funktionen,
  zentrale Fehlerbehandlung, deutschsprachige Ausgaben.

## Version 1.1.0 – 2026-08-22

- Dateikopf auf Styleguide 1.6.0 umgestellt (Pflichtfelder, Historie,
  Aufruf/Nutzung mit sudo in Beispielen).
- Autor auf `(FFHB) / RadioBBS` gesetzt; Upstream-Credit in Beschreibung.
- `--version` zeigt zusaetzlich Programmbeschreibung.
- Projektdateien ergaenzt: README, PROJECT.yaml, project.toml,
  pyproject.toml, requirements.txt, CHANGELOG.md, LICENSE-Metadaten,
  .gitignore/.gitattributes nach Styleguide.
- Eigenes privates Git-Repository unter GIT-Projects/PiShrink.
