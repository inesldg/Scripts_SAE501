#!/bin/bash

# Variables serveur
DEST_USER="backupserv"
DEST_HOST="87.106.123.52"
BACKUP_DATE=$(date '+%Y-%m-%d')
DEST_PATH="/home/backupserv/backup/${BACKUP_DATE}"

# Variables BDD
DB_USER="wp_admin"
DB_NAME="wordpress"
DB_PW="$1"
DB_PATH="/var/www/html/backup/${DB_NAME}.sql"

# Variables logs
DATE=$(date '+%Y-%m-%d %H:%M:%S')
LOGS="/var/log/server_backup.log"

# Connection au serveur et création du dossier de backup
sshpass -p "$1" ssh -o StrictHostKeyChecking=no ${DEST_USER}@${DEST_HOST} "mkdir -p ${DEST_PATH}"


# Début de la backup
echo "Début du transfert le ${DATE}"

# Suppression des anciennes backups
sshpass -p "$1" ssh -o StrictHostKeyChecking=no ${DEST_USER}@${DEST_HOST} \
"find /var/www/html/backup -mindepth 1 -maxdepth 1 -type d -mtime +1 -exec rm -rf {} \;"

# Transfert des fichiers / dossiers
sshpass -p "$1" rsync -avz -e "ssh -o StrictHostKeyChecking=no" \
"/var/www/html/wordpress" ${DEST_USER}@${DEST_HOST}:${DEST_PATH} >> "$LOGS" 2>&1


# Base de données
mysqldump -u ${DB_USER} -p"${DB_PW}" ${DB_NAME} > ${DB_PATH}

sshpass -p "$1" rsync -avz -e "ssh -o StrictHostKeyChecking=no" \
"${DB_PATH}" ${DEST_USER}@${DEST_HOST}:${DEST_PATH} >> "$LOGS" 2>&1

rm -f ${DB_PATH}


if [ $? -eq 0 ]; then
  echo "[\(DATE] Sauvegarde réussie" >> "\)LOGS"
else
  echo "[\(DATE] Erreur lors du transfert" >> "\)LOGS"
fi
