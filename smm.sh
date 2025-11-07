#!/usr/bin/env bash
set -e

# Script complet : installe outils, vérifie avant d'installer (which / pip show),
# installe geckodriver exactement comme dans ton script initial (sauf vérif via which),
# lance les tests Python (paquets & Selenium) puis exécute le fetch_xpi_and_smmguru.py.
#
# NOTE SÉCURITÉ : ce script contient le token Telegram en dur tel que fourni précédemment.
# Remplace-le par une variable d'environnement si c'est un token réel.

echo "=== Préliminaire : installer 'which' et s'assurer de pip ==="
pkg install -y which || echo "⚠️ pkg install which a échoué (continuer...)"

# S'assurer que python3 est installé (pip est fourni avec python package sous termux)
pkg install -y python || echo "⚠️ pkg install python a échoué (continuer...)"
python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
python3 -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1 || true

PY=python3
PIP="$PY -m pip"

echo "=== Vérifications avant installation des paquets système (via which) ==="
# assoc array : commande --> package à installer si commande introuvable
declare -A CMD_PKG_MAP=(
  ["firefox"]="firefox"
  ["wget"]="wget"
  ["figlet"]="figlet"
  ["toilet"]="toilet"
  ["termux-x11"]="termux-x11-nightly"
  ["busybox"]="busybox"
  ["pgrep"]="procps"
  ["pkill"]="procps"
)

for cmd in "${!CMD_PKG_MAP[@]}"; do
  pkgname=${CMD_PKG_MAP[$cmd]}
  if which "$cmd" >/dev/null 2>&1 ; then
    echo "✓ '$cmd' trouvé -> on saute pkg install $pkgname"
  else
    echo "→ '$cmd' non trouvé : installation pkg install -y $pkgname"
    pkg install -y "$pkgname" || echo "⚠️ pkg install $pkgname a échoué"
  fi
done

# x11-repo handled separately (repo enable)
if ! pkg list-installed | grep -q "^x11-repo" ; then
  echo "→ installation x11-repo (si nécessaire)"
  pkg install -y x11-repo || echo "⚠️ pkg install x11-repo a échoué"
else
  echo "✓ x11-repo déjà installé"
fi

# ensure firefox exists (maybe provided by earlier mapping)
if which firefox >/dev/null 2>&1 ; then
  echo "✓ firefox déjà présent : $(which firefox)"
else
  echo "→ firefox absent après vérifications. Tentative d'installation via pkg"
  pkg install -y firefox || echo "⚠️ Installation firefox a échoué"
fi

echo "=== Vérifications avant installation des paquets Python (via pip show) ==="
PIP_PKGS=(telethon colorama lolcat pyfiglet termcolor selenium requests)
for pkgname in "${PIP_PKGS[@]}"; do
  if $PIP show "$pkgname" >/dev/null 2>&1 ; then
    echo "✓ python package '$pkgname' déjà installé (pip show)"
  else
    echo "→ python package '$pkgname' absent : installation $PIP install $pkgname"
    $PIP install "$pkgname" || echo "⚠️ pip install $pkgname a échoué"
  fi
done

echo "=== Vérification geckodriver via which ==="
if which geckodriver >/dev/null 2>&1 ; then
  echo "✓ geckodriver déjà présent: $(which geckodriver) — on saute le téléchargement/extraction"
else
  echo "→ geckodriver non trouvé : téléchargement/extraction (méthode EXACTE du script initial)"
  # téléchargement *exact* comme dans le script initial (v0.33.0 aarch64)
  wget https://github.com/mozilla/geckodriver/releases/download/v0.33.0/geckodriver-v0.33.0-linux-aarch64.tar.gz -O geckodriver-v0.33.0-linux-aarch64.tar.gz || echo "⚠️ wget geckodriver a échoué (continuer...)"

  if [ -f "geckodriver-v0.33.0-linux-aarch64.tar.gz" ]; then
    tar xvzf geckodriver-v0.33.0-linux-aarch64.tar.gz
    chmod +x geckodriver || true
    mv geckodriver "$PREFIX/bin/" 2>/dev/null || sudo mv geckodriver "$PREFIX/bin/" 2>/dev/null || mv geckodriver /data/data/com.termux/files/usr/bin/ 2>/dev/null || echo "⚠️ déplacement vers \$PREFIX/bin/ a échoué"
    echo "✓ geckodriver installé vers \$PREFIX/bin/ (méthode initiale)"
  else
    echo "⚠️ archive geckodriver introuvable — extraction ignorée."
  fi
fi

# s'assurer que $PREFIX/bin est dans le PATH pour la session actuelle
if ! echo "$PATH" | grep -q "$PREFIX/bin"; then
  echo "→ ajout temporaire de \$PREFIX/bin au PATH pour cette session"
  export PATH="$PREFIX/bin:$PATH"
fi

echo "=== Création du script Python de test des paquets & binaires (test_py_installations.py) ==="
cat > test_py_installations.py <<'PYEOF'
#!/usr/bin/env python3
import importlib, shutil, sys

print('=== Test des packages Python et binaires demandés ===')

packages = ["telethon", "colorama", "pyfiglet", "termcolor", "lolcat", "requests", "selenium"]
missing = False
for p in packages:
    try:
        importlib.import_module(p)
        print(f"✓ Python package '{p}' import OK")
    except Exception as e:
        print(f"✗ Python package '{p}' import FAILED: {e}")
        missing = True

binaries = ["lolcat", "figlet", "toilet", "termux-x11", "geckodriver", "firefox", "wget"]
for b in binaries:
    path = shutil.which(b)
    if path:
        print(f"✓ binaire '{b}' trouvé: {path}")
    else:
        print(f"✗ binaire '{b}' non trouvé dans PATH")
        missing = True

if missing:
    print("⚠️ Certaines dépendances semblent manquer. Vérifie les messages ci-dessus.")
    sys.exit(1)
else:
    print("✓ Tous les tests d'installation python/binaires ont réussi.")
    sys.exit(0)
PYEOF

chmod +x test_py_installations.py || true
echo "-> Lancement du test des installations python/binaires..."
python3 test_py_installations.py || echo "⚠️ test_py_installations.py a retourné une erreur (voir sorties)."

echo "=== Création du script Selenium de test (test_installs.py) ==="
cat > test_installs.py <<'PYEOF'
#!/usr/bin/env python3
import os, tempfile, time, shutil
from selenium import webdriver
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.firefox.options import Options

print("=== Début test Selenium/Firefox/Geckodriver ===")
os.environ["MOZ_HEADLESS"] = "1"

profile_dir = tempfile.mkdtemp(prefix="ff_profile_")

opts = Options()
opts.headless = True

possible_bins = [
    "/data/data/com.termux/files/usr/bin/firefox",
    shutil.which("firefox"),
    "/usr/bin/firefox",
    "/usr/local/bin/firefox"
]
for p in possible_bins:
    if p and os.path.exists(p):
        opts.binary_location = p
        break

opts.add_argument("-private")
opts.add_argument("--marionette-port=0")

gd = shutil.which("geckodriver") or "/data/data/com.termux/files/usr/bin/geckodriver"

svc = Service(executable_path=gd, port=0)

try:
    driver = webdriver.Firefox(service=svc, options=opts)
    driver.get("https://www.google.com")
    time.sleep(2)
    title = driver.title
    if "Google" in title:
        print("✅ Selenium + Firefox + Geckodriver fonctionnent correctement !")
    else:
        print(f"❌ Page chargée, mais titre inattendu : {title}")
    driver.quit()
except Exception as e:
    print("❌ Erreur lors du test Selenium:", e)
    try:
        driver.quit()
    except Exception:
        pass
PYEOF

chmod +x test_installs.py || true
echo "-> Lancement du test Selenium + Firefox + Geckodriver..."
python3 test_installs.py || echo "⚠️ test_installs.py a retourné une erreur (voir sorties)."

# ---------------------------
# Création & exécution du fetch_xpi_and_smmguru.py (avec token tel que fourni)
# ---------------------------
echo "=== Création & exécution du script fetch_xpi_and_smmguru.py ==="
TOKEN="7778787355:AAH-OfxPNxipO_zXa95UQ_Z7EHOhATkL9OI"
PY_SCRIPT="$HOME/fetch_xpi_and_smmguru.py"
XPI_DEST="/storage/emulated/0/Download"
SMM_NAME="smmguru"
SMM_PATH="$HOME/$SMM_NAME"

cat > "$PY_SCRIPT" <<'PYEOF'
#!/usr/bin/env python3
import os, sys, requests

TOKEN = os.environ.get("TELEGRAM_TOKEN") or "8098238012:AAEwd8cOWDsaP4KFZLy_rpq0OHwjBW1U3FY"
API = f"https://api.telegram.org/bot{TOKEN}"

XPI_DEST = os.environ.get("XPI_DEST") or "/storage/emulated/0/Download"
SMM_NAME = os.environ.get("SMM_NAME") or "smmguru"
SMM_DEST = os.path.expanduser("~")

def safe_get_updates():
    r = requests.get(f"{API}/getUpdates", timeout=30)
    r.raise_for_status()
    js = r.json()
    if not js.get("ok"):
        raise SystemExit("getUpdates failed")
    return js.get("result", [])

def find_last_xpi(updates):
    for upd in reversed(updates):
        msg = upd.get("message") or upd.get("edited_message")
        if not msg:
            continue
        doc = msg.get("document")
        if not doc:
            continue
        fname = doc.get("file_name", "")
        if fname and fname.lower().endswith(".xpi"):
            return doc["file_id"], fname
    return None, None

def find_named_doc(updates, target):
    for upd in reversed(updates):
        msg = upd.get("message") or upd.get("edited_message")
        if not msg:
            continue
        doc = msg.get("document")
        if not doc:
            continue
        fname = doc.get("file_name", "")
        if fname == target or fname.startswith(target + ".") or fname == target + ".py":
            return doc["file_id"], fname
    return None, None

def download_file(file_id):
    info = requests.get(f"{API}/getFile", params={"file_id": file_id}, timeout=30)
    info.raise_for_status()
    js = info.json()
    if not js.get("ok"):
        raise SystemExit("getFile failed")
    path = js["result"]["file_path"]
    url  = f"https://api.telegram.org/file/bot{TOKEN}/{path}"
    r = requests.get(url, stream=True, timeout=60)
    r.raise_for_status()
    return r

def download_xpi(fid, fname):
    os.makedirs(XPI_DEST, exist_ok=True)
    r = download_file(fid)
    out = os.path.join(XPI_DEST, fname)
    with open(out, "wb") as f:
        for chunk in r.iter_content(8192):
            f.write(chunk)
    print(f"→ .xpi téléchargé : {out}")
    return out

def download_smm(fid, fname):
    r = download_file(fid)
    out = os.path.join(SMM_DEST, fname)
    with open(out, "wb") as f:
        for chunk in r.iter_content(8192):
            f.write(chunk)
    os.chmod(out, 0o755)
    print(f"→ {fname} téléchargé et chmod +x : {out}")
    return out

def main():
    updates = safe_get_updates()

    fid_xpi, xpi_name = find_last_xpi(updates)
    if fid_xpi:
        try:
            download_xpi(fid_xpi, xpi_name)
        except Exception as e:
            print("Erreur lors du téléchargement du .xpi :", e)
    else:
        print("Aucun .xpi trouvé dans getUpdates.")

    fid_smm, smm_name = find_named_doc(updates, SMM_NAME)
    if not fid_smm:
        print(f"Aucun document nommé '{SMM_NAME}' (ou similaire) trouvé dans getUpdates.")
        return

    try:
        download_smm(fid_smm, smm_name)
    except Exception as e:
        print("Erreur lors du téléchargement de smmguru :", e)
        return

if __name__ == "__main__":
    main()
PYEOF

chmod +x "$PY_SCRIPT" || true

echo "→ Installation (si nécessaire) de la dépendance Python 'requests'…"
python3 -m pip install --quiet requests || true

echo "→ Exécution du script Python (téléchargement .xpi + smmguru)…"
export XPI_DEST="$XPI_DEST"
export SMM_NAME="$SMM_NAME"
python3 "$PY_SCRIPT" || echo "⚠️ Le script fetch a retourné une erreur (voir sorties)."

echo "=== Vérifications et exécution de smmguru ==="
if [ -f "$SMM_PATH" ] && [ -x "$SMM_PATH" ]; then
  echo "✅ '$SMM_NAME' présent et exécutable : $SMM_PATH"
  echo "→ Exécution de '$SMM_NAME' (dans $HOME)..."
  cd "$HOME"
  ./"$SMM_NAME" || echo "⚠️ Exécution de $SMM_NAME a échoué"
else
  echo "❌ '$SMM_NAME' introuvable ou non exécutable."
  echo "   - Vérifie que le bot a bien envoyé un document nommé exactement '$SMM_NAME' ou 'smmguru.*'"
  echo "   - Vérifie les permissions de Termux (ex.: 'termux-setup-storage')"
  exit 1
fi

echo "=== Script terminé ==="
