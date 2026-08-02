#!/usr/bin/env bash
#
# =============================================================================
# pishrink.sh - Verkleinern von Raspberry-Pi-Image-Dateien
# =============================================================================
#
# Programmbeschreibung:
#   Bash-Skript zum automatischen Verkleinern von Raspberry-Pi-Image-Dateien.
#   Beim naechsten Boot kann das Dateisystem wieder auf die volle SD-Karten-
#   Groesse erweitert werden. Optional: gzip-/xz-Kompression inkl. Parallelmodus.
#
# Zweck:
#   Images nach dem Backup schrumpfen, damit Schreiben und Komprimieren
#   schneller und speicherfreundlicher werden.
#
# Autor:
#   Original: Drew Bonasera (Drewsif) - https://github.com/Drewsif/PiShrink
#   Deutsche Lokalisierung / Style-Guide: Cursor Assistant
#
# Version:
#   1.0.0
#
# Aenderungsverlauf:
#   - Version 26.03.16 - 2026-03-16 - Upstream PiShrink (Drewsif).
#   - Version 1.0.0    - 2026-08-02 - Deutsche Lokalisierung nach Style-Guide:
#     Header, Hilfe/Version, Logging mit Zeitstempel, --Ende/-E, dokumentierte
#     Funktionen, zentrale Fehlerbehandlung, deutschsprachige Ausgaben.
#
# Lizenz:
#   MIT (siehe LICENSE) - Open Source
#
# Upstream:
#   https://github.com/Drewsif/PiShrink
#
# Aufruf:
#   sudo ./pishrink.sh [-adhnrsvzZ] [--log] [--Ende|-E] image.img [neu.img]
#   ./pishrink.sh --help
#   ./pishrink.sh --version
#
# Parameter:
#   image.img / neu.img  Typ: Pfad  Standard: Pflicht / optional
#                        Quellimage; optional Kopie als Arbeitsdatei.
#                        Beispiel: pi.img pi-klein.img
#   -s                   Typ: Flag  Standard: aus
#                        Kein Autoexpand beim ersten Boot.
#   -v                   Typ: Flag  Standard: aus
#                        Ausfuehrliche Kompressor-Ausgabe.
#   -n                   Typ: Flag  Standard: aus
#                        Keine Upstream-Update-Pruefung.
#   -r                   Typ: Flag  Standard: aus
#                        Erweiterte Dateisystem-Reparatur.
#   -z                   Typ: Flag  Standard: aus
#                        Nach dem Schrumpfen mit gzip komprimieren.
#   -Z                   Typ: Flag  Standard: aus
#                        Nach dem Schrumpfen mit xz komprimieren.
#   -a                   Typ: Flag  Standard: aus
#                        Parallele Kompression (pigz / xz -T0).
#   -d / --log           Typ: Flag  Standard: aus
#                        Logging in pishrink.log (UTF-8, Zeitstempel).
#   -h / --help          Hilfe anzeigen und beenden.
#   --version            Version und Datum anzeigen und beenden.
#   -E / --Ende          Am Programmende auf Tastendruck warten.
#
# Voraussetzung:
#   Root-Rechte; Tools: parted, losetup, tune2fs, md5sum, e2fsck, resize2fs
# =============================================================================

# --- Globale Konstanten ------------------------------------------------------

VERSION="1.0.0"
VERSION_DATUM="2026-08-02"
UPSTREAM_VERSION="v26.03.16"
UPSTREAM_URL="https://github.com/Drewsif/PiShrink"

START_SEKUNDEN=$SECONDS
AKTUELLES_VERZEICHNIS="$(pwd)"
SKRIPTNAME="${0##*/}"
MEIN_NAME="${SKRIPTNAME%.*}"
LOGDATEI="${AKTUELLES_VERZEICHNIS}/${MEIN_NAME}.log"
END_PROMPT="Programmende: Hit any Key or Enter"

ERFORDERLICHE_WERKZEUGE="parted losetup tune2fs md5sum e2fsck resize2fs"
ZIP_WERKZEUGE=("gzip" "xz")
declare -A ZIP_PARALLEL_TOOL=( [gzip]="pigz" [xz]="xz" )
declare -A ZIP_PARALLEL_OPTIONEN=( [gzip]="-f9" [xz]="-T0" )
declare -A ZIP_ERWEITERUNGEN=( [gzip]="gz" [xz]="xz" )

# Laufzeit-Flags (werden in main gesetzt)
soll_autoexpand_ueberspringen=false
logging_aktiv=false
update_pruefung=true
reparatur=false
parallel=false
ausfuehrlich=false
warte_am_ende=false
zip_werkzeug=""
quellen_image=""
image_pfad=""
ziel_image_kopie=""
loopback=""
mount_verzeichnis=""
groesse_vorher=""
parted_ausgabe=""
part_nummer=""
part_start=""
part_typ=""
tune2fs_ausgabe=""
aktuelle_bloecke=""
block_groesse=""
exit_code=0

# --- Hilfsfunktionen ---------------------------------------------------------

zeitstempel() {
	#
	# Beschreibung: Liefert aktuellen Zeitstempel fuer Logzeilen.
	# Parameter: keine
	# Rueckgabewert: String YYYY-MM-DD HH:MM:SS auf stdout
	# Fehlerfaelle: date nicht verfuegbar
	# Beispiel: zeitstempel
	#
	date '+%Y-%m-%d %H:%M:%S'
}

log_nachricht() {
	#
	# Beschreibung: Schreibt eine Zeile in die Logdatei, falls Logging aktiv.
	# Parameter: $1 = Meldungstext
	# Rueckgabewert: keines
	# Fehlerfaelle: Schreibfehler auf LOGDATEI werden ignoriert
	# Beispiel: log_nachricht "Starte Pruefung"
	#
	local meldung="$1"
	[[ "$logging_aktiv" != true ]] && return 0
	printf '%s %s\n' "$(zeitstempel)" "$meldung" >> "$LOGDATEI"
}

info_meldung() {
	#
	# Beschreibung: Gibt eine Infozeile aus (bei --log via tee in der Logdatei).
	# Parameter: $1 = Meldung
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: info_meldung "Kopiere Image"
	#
	echo "$SKRIPTNAME: $1"
}

fehler_melden() {
	#
	# Beschreibung: Meldet einen Fehler mit Zeilennummer.
	# Parameter: $1 = Quellzeile, weitere = Meldung
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: fehler_melden $LINENO "Datei fehlt"
	#
	local zeile="$1"
	shift
	echo -n "$SKRIPTNAME: FEHLER in Zeile $zeile: "
	echo "$@"
}

beende_mit_fehler() {
	#
	# Beschreibung: Zentrale Fehlerbehandlung mit Exit-Code.
	# Parameter: $1 = Exit-Code, $2 = Zeile, weitere = Meldung
	# Rueckgabewert: beendet das Skript
	# Fehlerfaelle: ruft sich selbst final beendend auf
	# Beispiel: beende_mit_fehler 2 $LINENO "Kein Image"
	#
	local code="$1"
	local zeile="$2"
	shift 2
	fehler_melden "$zeile" "$@"
	exit_code="$code"
	exit "$code"
}

aufraeumen() {
	#
	# Beschreibung: Loest Loop-Device und stellt Log-Besitz wieder her.
	# Parameter: keine (nutzt globale Variablen)
	# Rueckgabewert: keines
	# Fehlerfaelle: losetup/chown koennen still scheitern
	# Beispiel: trap aufraeumen EXIT
	#
	if [[ -n "$loopback" ]] && losetup "$loopback" &>/dev/null; then
		losetup -d "$loopback"
	fi
	if [[ "$logging_aktiv" == true && -n "$quellen_image" && -f "$LOGDATEI" ]]; then
		local alter_besitzer
		alter_besitzer=$(stat -c %u:%g "$quellen_image" 2>/dev/null) || return 0
		chown "$alter_besitzer" "$LOGDATEI" 2>/dev/null || true
	fi
}

warte_auf_programmende() {
	#
	# Beschreibung: Wartet auf beliebige Taste / Enter (--Ende / -E).
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: nicht-interaktives Terminal -> still beenden
	# Beispiel: warte_auf_programmende
	#
	[[ "$warte_am_ende" != true ]] && return 0
	if [[ ! -t 0 ]]; then
		return 0
	fi
	echo "$END_PROMPT"
	# -n 1: eine Taste; -s: ohne Echo; -r: Backslash roh
	read -r -n 1 -s || true
	echo
}

log_variablen() {
	#
	# Beschreibung: Protokolliert Variablennamen und Werte in die Logdatei.
	# Parameter: $1 = Zeile, weitere = Variablennamen
	# Rueckgabewert: keines
	# Fehlerfaelle: ungesetzte Variablen werden als leer geloggt
	# Beispiel: log_variablen $LINENO image_pfad minsize
	#
	[[ "$logging_aktiv" != true ]] && return 0
	local zeile="$1"
	shift
	local name wert
	log_nachricht "DEBUG Zeile $zeile"
	for name in "$@"; do
		eval "wert=\${$name}"
		log_nachricht "DEBUG $name: $wert"
	done
}

zeige_version() {
	#
	# Beschreibung: Zeigt Versionsnummer und Datum.
	# Parameter: keine
	# Rueckgabewert: keines (stdout)
	# Fehlerfaelle: keine
	# Beispiel: zeige_version
	#
	echo "PiShrink $VERSION ($VERSION_DATUM)"
	echo "Basiert auf Upstream $UPSTREAM_VERSION - $UPSTREAM_URL"
}

zeige_hilfe() {
	#
	# Beschreibung: Zeigt Programmbeschreibung, Version, Parameter und Beispiele.
	# Parameter: keine
	# Rueckgabewert: keines (stdout)
	# Fehlerfaelle: keine
	# Beispiel: zeige_hilfe
	#
	cat << EOF
PiShrink $VERSION ($VERSION_DATUM)
Verkleinert Raspberry-Pi-Images; optional Autoexpand beim naechsten Boot.

Verwendung:
  sudo $0 [-adhnrsvzZ] [--log] [--Ende|-E] image.img [neu.img]
  $0 --help | -h
  $0 --version

Parameter:
  image.img          Quell-Image (Pflicht)
  neu.img            Optionale Arbeitskopie (benoetigt freien Speicher)

  -s                 Kein Dateisystem-Expand beim ersten Boot
  -v                 Ausfuehrliche Kompressor-Ausgabe
  -n                 Keine automatische Update-Pruefung (Upstream)
  -r                 Erweiterte Dateisystem-Reparatur bei Fehlern
  -z                 Nach dem Schrumpfen mit gzip komprimieren (.gz)
  -Z                 Nach dem Schrumpfen mit xz komprimieren (.xz)
  -a                 Parallele Kompression (pigz / xz -T0)
  -d, --log          Debug-/Lauf-Log in ${MEIN_NAME}.log schreiben
  -h, --help         Diese Hilfe anzeigen
  --version          Versionsnummer und Datum anzeigen
  -E, --Ende         Am Programmende auf Tastendruck warten

Umgebungsvariablen:
  PISHRINK_GZIP / PISHRINK_XZ   Ueberschreiben Kompressor-Optionen

Beispiele:
  sudo $0 pi.img
  sudo $0 -z -a pi.img pi-klein.img
  sudo $0 --log -E -r backup.img
EOF
}

pruefe_aktualisierung() {
	#
	# Beschreibung: Vergleicht lokale Upstream-Version mit GitHub-Release.
	# Parameter: keine
	# Rueckgabewert: keines; warnt bei neuerer Version
	# Fehlerfaelle: Netzwerkfehler werden still ignoriert
	# Beispiel: pruefe_aktualisierung
	#
	[[ "$update_pruefung" != true ]] && return 0
	local neueste
	neueste=$(curl -m 5 https://api.github.com/repos/Drewsif/PiShrink/releases/latest 2>/dev/null \
		| grep -i "tag_name" 2>/dev/null \
		| awk -F '"' '{print $4}' 2>/dev/null) || return 0
	if [[ -n "$neueste" && "$neueste" > "$UPSTREAM_VERSION" ]]; then
		echo "WARNUNG: Neuere Upstream-Version verfuegbar: $neueste"
		echo "Details: $UPSTREAM_URL"
		echo ""
		log_nachricht "WARNUNG Neuere Upstream-Version: $neueste"
	fi
}

pruefe_werkzeuge() {
	#
	# Beschreibung: Prueft, ob alle benoetigten Programme installiert sind.
	# Parameter: keine (nutzt ERFORDERLICHE_WERKZEUGE)
	# Rueckgabewert: keines; beendet bei Fehlern
	# Fehlerfaelle: Exit 4 / 17 bei fehlendem oder ungueltigem Werkzeug
	# Beispiel: pruefe_werkzeuge
	#
	local befehl
	if [[ -n $zip_werkzeug ]]; then
		if [[ ! " ${ZIP_WERKZEUGE[*]} " =~ $zip_werkzeug ]]; then
			beende_mit_fehler 17 $LINENO "$zip_werkzeug ist kein unterstuetztes Zip-Werkzeug."
		fi
		if [[ $parallel == true && $zip_werkzeug == "gzip" ]]; then
			ERFORDERLICHE_WERKZEUGE="$ERFORDERLICHE_WERKZEUGE pigz"
		else
			ERFORDERLICHE_WERKZEUGE="$ERFORDERLICHE_WERKZEUGE $zip_werkzeug"
		fi
	fi
	for befehl in $ERFORDERLICHE_WERKZEUGE; do
		if ! command -v "$befehl" >/dev/null 2>&1; then
			beende_mit_fehler 4 $LINENO "$befehl ist nicht installiert."
		fi
	done
}

kopiere_image_falls_noetig() {
	#
	# Beschreibung: Kopiert das Image auf Wunsch in eine neue Datei.
	# Parameter: $1 = Zielpfad (optional, aus Position 2)
	# Rueckgabewert: setzt image_pfad; Exit 5 bei Kopierfehler
	# Fehlerfaelle: cp schlaegt fehl
	# Beispiel: kopiere_image_falls_noetig "pi-neu.img"
	#
	local ziel="$1"
	[[ -z "$ziel" ]] && return 0

	if [[ -n $zip_werkzeug && "${ziel##*.}" == "${ZIP_ERWEITERUNGEN[$zip_werkzeug]}" ]]; then
		ziel="${ziel%.*}"
	fi
	info_meldung "Kopiere $quellen_image nach $ziel ..."
	if ! cp --reflink=auto --sparse=always "$quellen_image" "$ziel"; then
		beende_mit_fehler 5 $LINENO "Datei konnte nicht kopiert werden."
	fi
	local alter_besitzer
	alter_besitzer=$(stat -c %u:%g "$quellen_image")
	chown "$alter_besitzer" "$ziel"
	image_pfad="$ziel"
}

schreibe_autoexpand_rc_local() {
	#
	# Beschreibung: Schreibt rc.local fuer Rootfs-Expand beim naechsten Boot.
	# Parameter: $1 = Mount-Verzeichnis der Root-Partition
	# Rueckgabewert: keines
	# Fehlerfaelle: Schreibfehler auf dem Image-Dateisystem
	# Beispiel: schreibe_autoexpand_rc_local "$mount_verzeichnis"
	#
	local ziel_dir="$1"
	cat <<'EOFRC' > "$ziel_dir/etc/rc.local"
#!/bin/bash
## PiShrink https://github.com/Drewsif/PiShrink ##
do_expand_rootfs() {
  ROOT_PART=$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')

  PART_NUM=${ROOT_PART#mmcblk0p}
  if [ "$PART_NUM" = "$ROOT_PART" ]; then
    echo "$ROOT_PART is not an SD card. Don't know how to expand"
    return 0
  fi

  # Get the starting offset of the root partition
  PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d: | sed 's/[^0-9]//g')
  [ "$PART_START" ] || return 1
  # Return value will likely be error for fdisk as it fails to reload the
  # partition table because the root fs is mounted
  fdisk /dev/mmcblk0 <<EOF
p
d
$PART_NUM
n
p
$PART_NUM
$PART_START

p
w
EOF

cat <<EOF > /etc/rc.local &&
#!/bin/sh
echo "Expanding /dev/$ROOT_PART"
resize2fs /dev/$ROOT_PART
rm -f /etc/rc.local; cp -fp /etc/rc.local.bak /etc/rc.local && /etc/rc.local

EOF
reboot
exit
}
raspi_config_expand() {
/usr/bin/env raspi-config --expand-rootfs
if [[ $? != 0 ]]; then
  return -1
else
  rm -f /etc/rc.local; cp -fp /etc/rc.local.bak /etc/rc.local && /etc/rc.local
  reboot
  exit
fi
}
raspi_config_expand
echo "WARNING: Using backup expand..."
sleep 5
do_expand_rootfs
echo "ERROR: Expanding failed..."
sleep 5
if [[ -f /etc/rc.local.bak ]]; then
  cp -fp /etc/rc.local.bak /etc/rc.local
  /etc/rc.local
fi
exit 0
EOFRC
	chmod +x "$ziel_dir/etc/rc.local"
}

aktiviere_autoexpand() {
	#
	# Beschreibung: Aktiviert Rootfs-Autoexpand fuer den naechsten Pi-Boot.
	# Parameter: keine (nutzt loopback)
	# Rueckgabewert: keines; bricht bei Mount-Problemen warnend ab
	# Fehlerfaelle: Mount fehlgeschlagen, /etc fehlt
	# Beispiel: aktiviere_autoexpand
	#
	mount_verzeichnis=$(mktemp -d)
	partprobe "$loopback"
	sleep 3
	umount "$loopback" > /dev/null 2>&1
	if ! mount "$loopback" "$mount_verzeichnis" -o rw; then
		info_meldung "Loopback konnte nicht gemountet werden – Autoexpand bleibt aus."
		return 0
	fi
	if [[ ! -d "$mount_verzeichnis/etc" ]]; then
		info_meldung "/etc nicht gefunden – Autoexpand bleibt aus."
		umount "$mount_verzeichnis"
		return 0
	fi
	if [[ ! -f "$mount_verzeichnis/etc/rc.local" ]]; then
		info_meldung "Keine bestehende /etc/rc.local – Autoexpand kann fehlschlagen."
	fi
	if grep -q "## PiShrink https://github.com/Drewsif/PiShrink ##" "$mount_verzeichnis/etc/rc.local" 2>/dev/null; then
		umount "$mount_verzeichnis"
		return 0
	fi
	echo "Erstelle neue /etc/rc.local"
	if [[ -f "$mount_verzeichnis/etc/rc.local" ]]; then
		mv "$mount_verzeichnis/etc/rc.local" "$mount_verzeichnis/etc/rc.local.bak"
	fi
	schreibe_autoexpand_rc_local "$mount_verzeichnis"
	umount "$mount_verzeichnis"
}

pruefe_dateisystem() {
	#
	# Beschreibung: Prueft und repariert das ext-Dateisystem auf dem Loop-Device.
	# Parameter: keine
	# Rueckgabewert: keines; Exit 9 wenn Reparatur scheitert
	# Fehlerfaelle: e2fsck Exit-Code >= 4
	# Beispiel: pruefe_dateisystem
	#
	info_meldung "Pruefe Dateisystem"
	e2fsck -pf "$loopback"
	(( $? < 4 )) && return 0

	info_meldung "Dateisystemfehler erkannt."
	info_meldung "Versuche Wiederherstellung ..."
	e2fsck -y "$loopback"
	(( $? < 4 )) && return 0

	if [[ $reparatur == true ]]; then
		info_meldung "Versuche erweiterte Wiederherstellung (Phase 2) ..."
		e2fsck -fy -b 32768 "$loopback"
		(( $? < 4 )) && return 0
	fi
	beende_mit_fehler 9 $LINENO "Dateisystem-Wiederherstellung fehlgeschlagen."
}

sammle_image_daten() {
	#
	# Beschreibung: Ermittelt Partition, Startoffset, Typ und Blockgroessen.
	# Parameter: keine; setzt globale Variablen
	# Rueckgabewert: keines; Exit 6/7 bei Fehlern
	# Fehlerfaelle: parted/tune2fs schlagen fehl
	# Beispiel: sammle_image_daten
	#
	info_meldung "Ermittle Image-Daten"
	groesse_vorher="$(ls -lh "$image_pfad" | cut -d ' ' -f 5)"
	parted_ausgabe="$(parted -ms "$image_pfad" unit B print)"
	local rc=$?
	if (( rc )); then
		info_meldung "Moeglicherweise ungueltiges Image. Manuell: parted $image_pfad unit B print"
		beende_mit_fehler 6 $LINENO "parted fehlgeschlagen (rc $rc)"
	fi
	part_nummer="$(echo "$parted_ausgabe" | tail -n 1 | cut -d ':' -f 1)"
	part_start="$(echo "$parted_ausgabe" | tail -n 1 | cut -d ':' -f 2 | tr -d 'B')"
	if [[ -z "$(parted -s "$image_pfad" unit B print | grep "$part_start" | grep logical)" ]]; then
		part_typ="primary"
	else
		part_typ="logical"
	fi
	loopback="$(losetup -f --show -o "$part_start" "$image_pfad")"
	tune2fs_ausgabe="$(tune2fs -l "$loopback")"
	rc=$?
	if (( rc )); then
		echo "$tune2fs_ausgabe"
		beende_mit_fehler 7 $LINENO "tune2fs fehlgeschlagen. Dieser Image-Typ kann nicht verkleinert werden."
	fi
	aktuelle_bloecke="$(echo "$tune2fs_ausgabe" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)"
	block_groesse="$(echo "$tune2fs_ausgabe" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)"
	log_variablen $LINENO groesse_vorher parted_ausgabe part_nummer part_start part_typ \
		tune2fs_ausgabe aktuelle_bloecke block_groesse
}

verkleinere_dateisystem_und_partition() {
	#
	# Beschreibung: Schrumpft ext-FS, nullt freien Platz und passt Partition an.
	# Parameter: keine
	# Rueckgabewert: keines; Exit 10/12/13/14 bei Fehlern
	# Fehlerfaelle: resize2fs/parted
	# Beispiel: verkleinere_dateisystem_und_partition
	#
	local minsize extra_space part_neu_groesse neues_part_ende rc space
	if ! minsize=$(resize2fs -P "$loopback"); then
		rc=$?
		beende_mit_fehler 10 $LINENO "resize2fs fehlgeschlagen (rc $rc)"
	fi
	minsize=$(cut -d ':' -f 2 <<< "$minsize" | tr -d ' ')
	log_variablen $LINENO aktuelle_bloecke minsize

	if [[ $aktuelle_bloecke -eq $minsize ]]; then
		info_meldung "Dateisystem ist bereits minimal – ueberspringe Schrumpfen."
		return 0
	fi

	extra_space=$((aktuelle_bloecke - minsize))
	log_variablen $LINENO extra_space
	for space in 5000 1000 100; do
		if [[ $extra_space -gt $space ]]; then
			minsize=$((minsize + space))
			break
		fi
	done
	log_variablen $LINENO minsize

	info_meldung "Verkleinere Dateisystem"
	[[ -z "$mount_verzeichnis" ]] && mount_verzeichnis=$(mktemp -d)

	resize2fs -p "$loopback" "$minsize"
	rc=$?
	if (( rc )); then
		fehler_melden $LINENO "resize2fs fehlgeschlagen (rc $rc)"
		mount "$loopback" "$mount_verzeichnis"
		mv "$mount_verzeichnis/etc/rc.local.bak" "$mount_verzeichnis/etc/rc.local"
		umount "$mount_verzeichnis"
		losetup -d "$loopback"
		exit_code=12
		exit 12
	fi

	info_meldung "Nullen freien Speicherplatzes"
	mount "$loopback" "$mount_verzeichnis"
	cat /dev/zero > "$mount_verzeichnis/PiShrink_zero_file" 2>/dev/null || true
	info_meldung "Genullt: $(ls -lh "$mount_verzeichnis/PiShrink_zero_file" | cut -d ' ' -f 5)"
	rm -f "$mount_verzeichnis/PiShrink_zero_file"
	umount "$mount_verzeichnis"
	sleep 1

	info_meldung "Verkleinere Partition"
	part_neu_groesse=$((minsize * block_groesse))
	neues_part_ende=$((part_start + part_neu_groesse))
	log_variablen $LINENO part_neu_groesse neues_part_ende
	parted -s -a minimal "$image_pfad" rm "$part_nummer"
	rc=$?
	(( rc )) && beende_mit_fehler 13 $LINENO "parted fehlgeschlagen (rc $rc)"
	parted -s "$image_pfad" unit B mkpart "$part_typ" "$part_start" "$neues_part_ende"
	rc=$?
	(( rc )) && beende_mit_fehler 14 $LINENO "parted fehlgeschlagen (rc $rc)"
}

kuerze_image_datei() {
	#
	# Beschreibung: Schneidet unpartitionierten Platz am Image-Ende ab.
	# Parameter: keine
	# Rueckgabewert: keines; Exit 15/16 bei Fehlern
	# Fehlerfaelle: parted/truncate
	# Beispiel: kuerze_image_datei
	#
	info_meldung "Pruefe unpartitionierten Speicher"
	local endergebnis endergebnis_letzte rc
	endergebnis=$(parted -ms "$image_pfad" unit B print free)
	rc=$?
	(( rc )) && beende_mit_fehler 15 $LINENO "parted fehlgeschlagen (rc $rc)"

	endergebnis_letzte=$(tail -1 <<< "$endergebnis")
	[[ "$endergebnis_letzte" != *free\; ]] && return 0

	info_meldung "Kuerze Image-Datei"
	endergebnis=$(cut -d ':' -f 2 <<< "$endergebnis_letzte" | tr -d 'B')
	log_variablen $LINENO endergebnis
	truncate -s "$endergebnis" "$image_pfad"
	rc=$?
	(( rc )) && beende_mit_fehler 16 $LINENO "truncate fehlgeschlagen (rc $rc)"
}

komprimiere_image() {
	#
	# Beschreibung: Komprimiert das verkleinerte Image mit gzip oder xz.
	# Parameter: keine
	# Rueckgabewert: aktualisiert image_pfad; Exit 18/19 bei Fehlern
	# Fehlerfaelle: Kompressor-Fehler
	# Beispiel: komprimiere_image
	#
	[[ -z $zip_werkzeug ]] && return 0

	local optionen="" env_name parallel_tool rc
	env_name="${MEIN_NAME^^}_${zip_werkzeug^^}"
	[[ $parallel == true ]] && optionen="${ZIP_PARALLEL_OPTIONEN[$zip_werkzeug]}"
	[[ -v $env_name ]] && optionen="${!env_name}"
	[[ $ausfuehrlich == true ]] && optionen="$optionen -v"

	if [[ $parallel == true ]]; then
		parallel_tool="${ZIP_PARALLEL_TOOL[$zip_werkzeug]}"
		info_meldung "Komprimiere parallel mit $parallel_tool"
		# shellcheck disable=SC2086
		if ! $parallel_tool ${optionen} "$image_pfad"; then
			rc=$?
			beende_mit_fehler 18 $LINENO "$parallel_tool fehlgeschlagen (rc $rc)"
		fi
	else
		info_meldung "Komprimiere mit $zip_werkzeug"
		# shellcheck disable=SC2086
		if ! $zip_werkzeug ${optionen} "$image_pfad"; then
			rc=$?
			beende_mit_fehler 19 $LINENO "$zip_werkzeug fehlgeschlagen (rc $rc)"
		fi
	fi
	image_pfad="${image_pfad}.${ZIP_ERWEITERUNGEN[$zip_werkzeug]}"
}

parse_argumente() {
	#
	# Beschreibung: Parst Lang- und Kurzoptionen inkl. Style-Guide-Flags.
	# Parameter: alle CLI-Argumente als "$@"
	# Rueckgabewert: setzt Flags und Positionsargumente; Exit bei Hilfe/Version
	# Fehlerfaelle: unbekannte Optionen -> Hilfe und Exit 1
	# Beispiel: parse_argumente "$@"
	#
	local -a rest_args=()
	local zeige_hilfe_flag=false
	local zeige_version_flag=false
	local opt

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--help)
				zeige_hilfe_flag=true
				shift
				;;
			--version)
				zeige_version_flag=true
				shift
				;;
			--log)
				logging_aktiv=true
				shift
				;;
			--Ende)
				warte_am_ende=true
				shift
				;;
			--)
				shift
				rest_args+=("$@")
				break
				;;
			-*)
				rest_args+=("$1")
				shift
				;;
			*)
				rest_args+=("$1")
				shift
				;;
		esac
	done
	set -- "${rest_args[@]}"

	OPTIND=1
	while getopts ":adnhrsvzZE" opt; do
		case "${opt}" in
			a) parallel=true ;;
			d) logging_aktiv=true ;;
			n) update_pruefung=false ;;
			h) zeige_hilfe_flag=true ;;
			r) reparatur=true ;;
			s) soll_autoexpand_ueberspringen=true ;;
			v) ausfuehrlich=true ;;
			z) zip_werkzeug="gzip" ;;
			Z) zip_werkzeug="xz" ;;
			E) warte_am_ende=true ;;
			*)
				echo "Ungueltiger Parameter: -$OPTARG" >&2
				zeige_hilfe
				warte_auf_programmende
				exit 1
				;;
		esac
	done
	shift $((OPTIND - 1))
	quellen_image="$1"
	image_pfad="$1"
	ziel_image_kopie="$2"

	if [[ "$zeige_version_flag" == true ]]; then
		zeige_version
		warte_auf_programmende
		exit 0
	fi
	if [[ "$zeige_hilfe_flag" == true ]]; then
		zeige_hilfe
		warte_auf_programmende
		exit 0
	fi
}

# --- Hauptprogramm -----------------------------------------------------------

main() {
	#
	# Beschreibung: Orchestriert Pruefung, Schrumpfen, Kuerzen und Kompression.
	# Parameter: CLI-Argumente
	# Rueckgabewert: Exit-Code 0 bei Erfolg
	# Fehlerfaelle: diverse Exit-Codes 1-19 analog Upstream
	# Beispiel: main "$@"
	#
	parse_argumente "$@"
	trap 'aufraeumen; warte_auf_programmende' EXIT

	if [[ "$logging_aktiv" == true ]]; then
		info_meldung "Erstelle Logdatei $LOGDATEI"
		rm -f "$LOGDATEI" &>/dev/null
		exec 1> >(stdbuf -i0 -o0 -e0 tee -a "$LOGDATEI" >&1)
		exec 2> >(stdbuf -i0 -o0 -e0 tee -a "$LOGDATEI" >&2)
		log_nachricht "===== PiShrink $VERSION gestartet ====="
	fi

	echo -e "PiShrink $VERSION ($VERSION_DATUM) – Upstream $UPSTREAM_VERSION"
	echo -e "$UPSTREAM_URL\n"

	pruefe_aktualisierung

	if [[ -z "$image_pfad" ]]; then
		zeige_hilfe
		exit 1
	fi
	if [[ ! -f "$image_pfad" ]]; then
		beende_mit_fehler 2 $LINENO "$image_pfad ist keine Datei."
	fi
	if (( EUID != 0 )); then
		beende_mit_fehler 3 $LINENO "Root-Rechte erforderlich (sudo)."
	fi

	# Locale nur fuer dieses Skript und Kindprozesse auf POSIX stellen
	export LANGUAGE=POSIX
	export LC_ALL=POSIX
	export LANG=POSIX

	pruefe_werkzeuge
	kopiere_image_falls_noetig "$ziel_image_kopie"
	sammle_image_daten

	if [[ "$part_typ" == "logical" ]]; then
		echo "WARNUNG: Autoexpand fuer logische Partitionen wird noch nicht unterstuetzt."
	elif [[ "$soll_autoexpand_ueberspringen" == false ]]; then
		aktiviere_autoexpand
	else
		echo "Autoexpand wird uebersprungen ..."
	fi

	pruefe_dateisystem
	verkleinere_dateisystem_und_partition
	kuerze_image_datei
	komprimiere_image

	local groesse_nachher
	groesse_nachher=$(ls -lh "$image_pfad" | cut -d ' ' -f 5)
	log_variablen $LINENO groesse_nachher

	local ende_sekunden verstrichen
	ende_sekunden=$SECONDS
	verstrichen=$((ende_sekunden - START_SEKUNDEN))
	info_meldung "Verkleinert: $image_pfad von $groesse_vorher auf $groesse_nachher in $((verstrichen / 60))m $((verstrichen % 60))s"
	log_nachricht "===== PiShrink beendet (OK) ====="
	exit_code=0
}

main "$@"
