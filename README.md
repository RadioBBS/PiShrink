# PiShrink (deutsch)

Bash-Skript zum automatischen Verkleinern von Raspberry-Pi-Image-Dateien. Nach dem Schrumpfen kann das Root-Dateisystem beim ersten Boot wieder auf die volle SD-Kartengroesse wachsen. Optional lassen sich die Images mit gzip oder xz (auch parallel) komprimieren.

Dies ist eine **deutsche Lokalisierung** von [Drewsif/PiShrink](https://github.com/Drewsif/PiShrink) nach dem hauseigenen Style-Guide (Hilfe/Version, Logging, `--Ende`, dokumentierte Funktionen).

| | |
|---|---|
| Version | 1.0.0 (2026-08-02) |
| Upstream | v26.03.16 |
| Lizenz | MIT |

## Verwendung

```text
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
| `-h` / `--help` | Hilfe |
| `--version` | Versionsnummer und Datum |
| `-E` / `--Ende` | Am Ende auf Tastendruck warten |

Kompressor-Optionen lassen sich ueber `PISHRINK_GZIP` bzw. `PISHRINK_XZ` ueberschreiben.

## Voraussetzungen

- Root-Rechte (`sudo`)
- Letzte Partition muss **ext2/ext3/ext4** sein (nur diese wird verkleinert)
- Pakete (Debian/Ubuntu):  
  `sudo apt update && sudo apt install -y wget parted gzip pigz xz-utils udev e2fsprogs`
- VirtualBox-Shared-Folders: Image zuerst lokal auf die VM kopieren
- Unter Systemd ggf. [rc.local-Kompatibilitaet](https://www.linuxbabe.com/linux-server/how-to-enable-etcrc-local-with-systemd) aktivieren

## Installation

### Linux

```bash
chmod +x pishrink.sh
sudo cp pishrink.sh /usr/local/bin/pishrink
```

### Windows (WSL 2)

1. `wsl --install -d Debian` (Admin-CMD), ggf. neu starten  
2. Debian oeffnen, Pakete wie oben installieren  
3. Skript installieren; Windows-Laufwerke liegen unter `/mnt/c/` usw.

### macOS (Docker)

```bash
docker build -t pishrink .
# Beispiel-Alias (Apple Silicon / zsh):
alias pishrink='docker run -it --rm --platform linux/arm64 --privileged=true -v "$(pwd)":/workdir pishrink'
```

Ins Verzeichnis mit dem `.img` wechseln; relative Pfade verwenden.

## Beispiel

```bash
sudo ./pishrink.sh pi.img
# ... e2fsck / resize2fs ...
# pishrink.sh: Verkleinert: pi.img von 30G auf 3.1G in 2m 15s
```

```bash
sudo ./pishrink.sh -z -a --log -E backup.img backup-klein.img
```

## Analyse (Upstream)

PiShrink mountet die letzte Partition eines Disk-Images ueber `losetup`, prueft sie mit `e2fsck`, ermittelt die Minimalgroesse per `resize2fs -P`, schrumpft Dateisystem und Partition, schneidet unpartitionierten Speicher mit `truncate` ab und kann optional komprimieren. Fuer Autoexpand wird eine `rc.local` auf dem Image hinterlegt (raspi-config, sonst Fallback per `fdisk`/`resize2fs`).

## Mitwirken / Herkunft

Fehler und Features bitte idealerweise auch upstream melden:  
https://github.com/Drewsif/PiShrink

Originalautor: Drew Bonasera (MIT-Lizenz).
