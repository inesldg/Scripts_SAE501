#!/bin/bash
set -e

PANDA_VERSION="2.2.3"
NUMPY_VERSION="2.4.6"

IP_PROD="87.106.3.165"
IP_DEV="87.106.123.60"
DOSSIER_APP="/var/www/api-reco"
DOSSIER_ACTUEL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" #récupérer le chemin du dossier où est ce script

echo "Installation de Python..."
apt-get update -qq #actualisation des logiciels dispo sur le vps
apt-get install -y -qq python3-venv curl #installation python avec paquet pour créer environnement virtuels

echo "Copie de app_reco.py et reco.pkl dans $DOSSIER_APP..."
mkdir -p "$DOSSIER_APP" #on crée le dossier api-reco dans www, et on y copie les fichiers présents dans le github
cp "$DOSSIER_ACTUEL/app_reco.py" "$DOSSIER_APP/app_reco.py"
cp "$DOSSIER_ACTUEL/reco.pkl" "$DOSSIER_APP/reco.pkl"

echo "Installation des librairies Python..."
python3 -m venv "$DOSSIER_APP/venv" #création envioronment virtuel python
#flask pour les routes, gunicorn pour 24/24, puis les versions forcées de panda et numpy pour que ça amrche comme dans le Google Collab
"$DOSSIER_APP/venv/bin/pip" install -q flask gunicorn "pandas==$PANDA_VERSION" "numpy==$NUMPY_VERSION" #pip = gestionnaire de paquets python (équivalent de npm)

#Mise en place d'un fichier service (avec systemd) pour pouvoir faire touner 24/24 l'ia
echo "Configuration du démarrage automatique au reboot..."
cat << EOF > /etc/systemd/system/api-reco.service
[Unit]
Description=API Recommandation IA
After=network.target

[Service]
User=www-data
WorkingDirectory=$DOSSIER_APP
ExecStart=$DOSSIER_APP/venv/bin/gunicorn -w 2 -b 0.0.0.0:8000 app_reco:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chown -R www-data:www-data "$DOSSIER_APP"
systemctl daemon-reload
systemctl enable api-reco
systemctl restart api-reco

echo "Sécurisation du pare-feu..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow from "$IP_PROD" to any port 8000 >/dev/null
  ufw allow from "$IP_DEV" to any port 8000 >/dev/null
fi

echo "Configuartion du VPS pour les IA terminée !"
