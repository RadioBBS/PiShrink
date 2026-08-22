# PiShrink (deutsch)

```
PiShrink – Raspberry-Pi-Image-Dateien verkleinern.

Projekt:     PiShrink
Modul:       README.md
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

Bash-Skript zum automatischen Verkleinern von Raspberry-Pi-Image-Dateien. Nach dem Schrumpfen kann das Root-Dateisystem beim ersten Boot wieder auf die volle SD-Kartengroesse wachsen. Optional lassen sich die Images mit gzip oder xz (auch parallel) komprimieren.

Deutsche Lokalisierung von [Drewsif/PiShrink](https://github.com/Drewsif/PiShrink) nach Styleguide 1.6.0 (Hilfe/Version, Logging, `--Ende`, sudo in Beispielen, dokumentierte Funktionen).

| | |
|---|---|
| Version | 1.1.0 (2026-08-22) |
| Upstream | v26.03.16 |
| Lizenz | MIT |

## Verwendung

Start in WSL/Linux (bash); die Ausfuehrung benoetigt Root-Rechte (`sudo`):

```bash
sudo ./pishrink.sh [-adhnrsvzZ] [--log] [--Ende|-E] image.img [neu.img]
./pishrink.sh --help
./pishrink.sh --version
```

| Parameter | Beschreibung |
|---|---|
| `image.img` | Quell-Image (Pflicht) |
| `neu.img` | Optionale Arbeitskopie (benoetigt freien Speicher fuer eine volle Kopie) |
| `-s` | Kein Autoexpand beim ersten Boot |
| `-v` | Ausfuehrliche Kompressor-Ausgabe |
| `-n` | Keine Upstream-Update-Pruefung |
| `-r` | Erweiterte Dateisystem-Reparatur |
| `-z` | Nach dem Schrumpfen mit gzip komprimieren (`.gz`) |
| `-Z` | Nach dem Schrumpfen mit xz komprimieren (`.xz`) |
| `-a` | Parallele Kompression (`pigz` / `xz -T0`) |
| `-d` / `--log` | Lauf-Log in `pishrink.log` (UTF-8, Debug-Zeitstempel) |
| `-h` / `--help` | Hilfe (ohne sudo) |
| `--version` | Versionsnummer, Datum und Programmbeschreibung (ohne sudo) |
| `-E` / `--Ende` | Am Ende auf Tastendruck warten |

Kompressor-Optionen lassen sich ueber `PISHRINK_GZIP` bzw. `PISHRINK_XZ` ueberschreiben.

## Voraussetzungen

- Root-Rechte (`sudo`)
- Letzte Partition muss **ext2/ext3/ext4** sein (nur diese wird verkleinert)
- Pakete (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y wget parted gzip pigz xz-utils udev e2fsprogs
```

- VirtualBox-Shared-Folders: Image zuerst lokal auf die VM kopieren
- Unter Systemd ggf. [rc.local-Kompatibilitaet](https://www.linuxbabe.com/linux-server/how-to-enable-etcrc-local-with-systemd) aktivieren

## Installation

### Linux

```bash
chmod +x pishrink.sh
sudo cp pishrink.sh /usr/local/bin/pishrink
```

### Windows (WSL 2)

1. `wsl --install -d Debian` (CMD als Administrator), ggf. neu starten
2. Debian oeffnen, Pakete wie oben installieren
3. Skript installieren; Windows-Laufwerke liegen unter `/mnt/c/` usw.

### macOS (Docker)

```bash
docker build -t pishrink .
# Beispiel-Alias (Apple Silicon / zsh):
alias pishrink='docker run -it --rm --platform linux/arm64 --privileged=true -v "$(pwd)":/workdir pishrink'
```

Ins Verzeichnis mit dem `.img` wechseln; relative Pfade verwenden.

## Beispiele

```bash
sudo ./pishrink.sh pi.img
sudo ./pishrink.sh -z -a --log -E backup.img backup-klein.img
```

## Analyse (Upstream)

PiShrink mountet die letzte Partition eines Disk-Images ueber `losetup`, prueft sie mit `e2fsck`, ermittelt die Minimalgroesse per `resize2fs -P`, schrumpft Dateisystem und Partition, schneidet unpartitionierten Speicher mit `truncate` ab und kann optional komprimieren. Fuer Autoexpand wird eine `rc.local` auf dem Image hinterlegt (raspi-config, sonst Fallback per `fdisk`/`resize2fs`).

## Historie

- Upstream v26.03.16 – 2026-03-16 – Original PiShrink (Drewsif).
- Version 1.0.0 – 2026-08-02 – Deutsche Lokalisierung nach Styleguide.
- Version 1.1.0 – 2026-08-22 – Styleguide 1.6.0, Git-Repo, Projektdateien.

## Mitwirken / Herkunft

Fehler und Features bitte idealerweise auch upstream melden:  
https://github.com/Drewsif/PiShrink

Originalautor: Drew Bonasera (MIT-Lizenz). Deutsche Lokalisierung: (FFHB) / RadioBBS.
