#!/usr/bin/env bash
# Builds the Windows installer around an exported Godot game.
#   tools/installer/build.sh <version> <path/to/JohnsBeerRun.exe> <out dir>
# Needs Go 1.22+ and Python 3. Works on Linux, macOS or Windows (Git Bash) and in GitHub Actions.
set -euo pipefail
VER="$1"; GAME="$2"; OUT="$(mkdir -p "$3" && cd "$3" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
mkdir -p "$OUT"
cp "$GAME" "$HERE/setup/JohnsBeerRun.exe"
cp "$HERE/game.ico" "$HERE/setup/game.ico"
python3 - "$HERE" "$ROOT" "$VER" <<'PY'
import sys, base64
here, root, ver = sys.argv[1:4]
b64 = lambda p: base64.b64encode(open(p, 'rb').read()).decode()
fx = root + '/assets/fx/'
fonts = """<style>
@font-face{font-family:"Alfa Slab One";src:url(data:font/ttf;base64,%s) format("truetype");font-display:block}
@font-face{font-family:"Rye";src:url(data:font/ttf;base64,%s) format("truetype");font-display:block}
@font-face{font-family:"Archivo";src:url(data:font/ttf;base64,%s) format("truetype");font-weight:100 900;font-stretch:62%% 125%%;font-display:block}
</style>""" % (b64(fx + 'AlfaSlabOne-Regular.ttf'), b64(fx + 'Rye-Regular.ttf'), b64(fx + 'Archivo.ttf'))
ui = open(here + '/setup/ui_src.html').read()
ui = ui.replace('{{FONTS}}', fonts).replace('{{ART}}', 'data:image/jpeg;base64,' + b64(here + '/setup/art.jpg'))
ui = ui.replace('{{ICON}}', 'data:image/png;base64,' + b64(here + '/fav64.png')).replace('{{VERSION}}', ver)
assert '{{' not in ui
open(here + '/setup/ui.html', 'w').write(ui)
PY
cd "$HERE"
NUM="$(echo "$VER" | sed 's/[^0-9.].*//')"; while [ "$(echo "$NUM" | tr -cd . | wc -c)" -lt 3 ]; do NUM="$NUM.0"; done
# icon, manifest and version info for Setup.exe (llvm-rc if present, else go-winres)
if command -v llvm-rc >/dev/null && command -v llvm-cvtres >/dev/null; then
  C="$(echo "$NUM" | tr . ,)"
  cat > setup/app.rc <<RC
1 ICON "../game.ico"
1 24 "app.manifest"
1 VERSIONINFO
FILEVERSION $C
PRODUCTVERSION $C
FILEOS 0x40004
FILETYPE 0x1
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904b0"
    BEGIN
      VALUE "CompanyName", "Cessna"
      VALUE "FileDescription", "John's Beer Run Setup"
      VALUE "FileVersion", "$NUM"
      VALUE "ProductName", "John's Beer Run"
      VALUE "ProductVersion", "$VER"
      VALUE "OriginalFilename", "JohnsBeerRun-Setup.exe"
      VALUE "LegalCopyright", "Created by Cessna"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
RC
  (cd setup && llvm-rc -fo app.res app.rc && llvm-cvtres /machine:x64 /out:rsrc_windows_amd64.syso app.res && rm -f app.res app.rc)
else
  go run github.com/tc-hib/go-winres@v0.3.3 simply --arch amd64 --out setup/rsrc --icon game.ico --manifest gui \
    --product-version "$NUM" --file-version "$NUM" --file-description "John's Beer Run Setup" --product-name "John's Beer Run" \
    --copyright "Created by Cessna" --original-filename "JohnsBeerRun-Setup.exe"
fi
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -H windowsgui -X main.version=$VER" -o "$OUT/JohnsBeerRun-Setup-v$VER.exe" ./setup
rm -f setup/JohnsBeerRun.exe setup/game.ico setup/ui.html setup/rsrc_windows_*.syso
echo "built $OUT/JohnsBeerRun-Setup-v$VER.exe"
