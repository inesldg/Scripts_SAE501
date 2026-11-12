#!/bin/bash
set -e # Arrêt du script immédiat en cas d'erreur de téléchargement
# ======================================================================
# SCRIPT DE DEPLOIEMENT DU SERVEUR DE MONITORING (PROMETHEUS + GRAFANA)
# ======================================================================

echo "Mise à jour du système..."
apt update -y && apt upgrade -y

# ----------------------------------------------------------
# 1. INSTALLATION ET CONFIGURATION DE PROMETHEUS
# ----------------------------------------------------------
echo "Téléchargement et installation de Prometheus..."
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar -xzf prometheus-2.45.0.linux-amd64.tar.gz

# Déplacement des fichiers exécutables
cp prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
cp prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
rm -rf prometheus-2.45.0.linux-amd64*

# Création du dossier de configuration et de stockage des données
mkdir -p /etc/prometheus /var/lib/prometheus

echo "Création du fichier de configuration prometheus.yml..."
cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  # Le serveur de monitoring se surveille lui-même
  - job_name: 'vps_monitoring'
    static_configs:
      - targets: ['localhost:9090']

  # Surveillance du VPS de PROD (Port 9100)
  - job_name: 'vps_prod'
    static_configs:
      - targets: ['ip87-106-3-165.pbiaas.com:9100']

  # Surveillance du VPS de DEV (Port 9100)
  - job_name: 'vps_dev'
    static_configs:
      - targets: ['ip87-106-123-60.pbiaas.com:9100']

  # Surveillance du VPS de BACKUP (Port 9100)
  - job_name: 'vps_backup'
    static_configs:
      - targets: ['87.106.123.52:9100']
EOF
sed -i 's/\xc2\xa0/ /g' /etc/prometheus/prometheus.yml #correection des erreurs de syntaxe

# Vérification automatique de la syntaxe YAML avant lancement
promtool check config /etc/prometheus/prometheus.yml

echo "Création et activation du service systemd Prometheus..."
cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Serveur de supervision Prometheus
After=network.target

[Service]
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now prometheus
echo "Prometheus est installé et démarré sur le port 9090 !"

# ----------------------------------------------------------
# 2. INSTALLATION AUTOMATIQUE DE GRAFANA
# ----------------------------------------------------------
echo "Téléchargement et installation de Grafana..."
cd /tmp
apt-get install -y adduser libfontconfig1 musl
wget -q https://dl.grafana.com/oss/release/grafana_11.0.0_amd64.deb
dpkg -i grafana_11.0.0_amd64.deb
rm -f grafana_11.0.0_amd64.deb

# ----------------------------------------------------------
# 3. LIAISON PROMETHEUS + DASHBOARD
# ----------------------------------------------------------
echo "Configuration automatique de la Data Source Prometheus dans Grafana..."
mkdir -p /etc/grafana/provisioning/datasources
cat <<EOF > /etc/grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF
sed -i 's/\xc2\xa0/ /g' /etc/grafana/provisioning/datasources/prometheus.yaml #correction des erreurs de syntaxe

echo "Téléchargement et import automatique du Dashboard Node Exporter Full (1860)..."
mkdir -p /var/lib/grafana/dashboards
wget -q -O /var/lib/grafana/dashboards/node-exporter-full.json "https://grafana.com/api/dashboards/1860/revisions/37/download"
chown -R grafana:grafana /var/lib/grafana/dashboards

mkdir -p /etc/grafana/provisioning/dashboards
cat <<EOF > /etc/grafana/provisioning/dashboards/default.yaml
apiVersion: 1
providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF
sed -i 's/\xc2\xa0/ /g' /etc/grafana/provisioning/dashboards/default.yaml #correction des erreurs de syntaxe

# Redémarrage de Grafana pour appliquer la configuration automatique
systemctl daemon-reload
systemctl enable --now grafana-server
systemctl restart grafana-server

echo "=========================================================="
echo "   INSTALLATION DU MONITORING TERMINEE AVEC SUCCES !      "
echo "=========================================================="
echo " Accès Prometheus : http://$(hostname -I | awk '{print $1}'):9090"
echo " Accès Grafana    : http://$(hostname -I | awk '{print $1}'):3000"
echo " (Identifiants Grafana par défaut : admin / admin)"
echo " Note : Prometheus et le Dashboard 1860 sont déjà liés !"
echo "=========================================================="
