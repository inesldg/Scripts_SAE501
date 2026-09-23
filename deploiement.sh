#!/bin/bash

#SCRIPT DE DEPLOIEMENT DU SITE VERS LE SERVEUR 

#Vérifie si un argument a été entré lors de l'exécution (il enregistrera ce mdp pour créer l'utilisateur)
if [[ -z "$1" ]]; then
    echo "Problème avec le mot de passe"
    exit 1
fi

#Gestion meémoire swap: mémoire de secours sur un autre vps pour stocker un surplus de données et éviter un crash du site
dd if=/dev/zero of=/fichier_swap bs=1024 count=1048576 # crée un fichier de 1GO
chmod 600 /fichier_swap # restreint les accès que à root
mkswap /fichier_swap # formate le fichier pour que linux l'utilise comme mémoire virtuelle 
swapon /fichier_swap # active le swap

#Apparition automatique du swap au démarrage du vps (en cas de crash par exemple)
FICHIER_SWAP=""

#Vérifier si le fichier swap n'existe pas dans le file system table (fichier conf contenant les fichiers de stockage)
#Linux saura qu'il doit réactiver ce swap à chaque boot 
if ! grep -q "/fichier_swap" /etc/fstab; then
    echo "/fichier_swap none swap sw 0 0" >> /etc/fstab
    # ajoute la ligne de config du swap à la fin du fichier fstab pour qu'il soit réactivé à chaque boot du vps
    FICHIER_SWAP="Ligne ajoutée dans le fichier /etc/fstab"
    echo "$FICHIER_SWAP"
else
    FICHIER_SWAP="La ligne existe déjà dans /etc/fstab ! :)"
    echo "$FICHIER_SWAP"
fi

#Mise à jour des programmes du vps et de l'éditeur de texte vim
echo "Mise à jour du VPS..."
apt update -y
apt install -y vim

#Création d'un utilisateur pour le vps
USER_VPS=""

# Création du compte admin (-m crée le dossier utilisateur et -s bin bash attribue le terminal bash)
if useradd -m -s /bin/bash -G sudo admin; then #-G sudo ajoute admin au groupe sudo pour pouvoir exécuter des commandes admin
    echo "admin:$1" | chpasswd #Attribue l'argument ajouté lors de l'exécution du script en tant que mot de passe

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak # copie du fichier sshd avant de le modifier (le .bak sera juste ignoré, il sert de backup)
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config # ajout de "permitrootlogin no" à la fin du fichier de config ssh (il remplace la ligne du dessus qui dit yes)
    echo "Redémarrage du module ssh..."
    systemctl restart ssh # relancer le module ssh
    USER_VPS="L'utilisateur admin a bien été créé, et le module SSH est bien configuré !"
else
    USER_VPS="L'utilisateur admin n'a pas pu être créé (il existait déjà ou une erreur est survenue) :("
fi
echo "$USER_VPS"

#INSTALLATION DE TOUT LE SERVUER
echo "Installation du stack LAMP..."

#Initialisation des variables
APACHE=""
PHP=""
MARIADB=""
NODEJS=""
GIT=""

#Installation de apache2
if apt install apache2 -y; then
    APACHE="Apache installé avec succès :) !"
else
    APACHE="Une erreur est survenue lors de l'installation de Apache2 :("
fi

#Installation de php et de tout les modules woocommerc etc
if apt install php libapache2-mod-php php-mysql php-curl php-gd php-xml php-mbstring php-zip php-intl php-imagick -y; then
    PHP="PHP installé avec succès :) !"
else
    PHP="Une erreur est survenue lors de l'installation de PHP :("
fi

#Installation de mariadb
if apt install mariadb-server -y; then
    MARIADB="MariaDB installé avec succès :) !"
else
    MARIADB="Une erreur est survenue lors de l'installation de MariaDB :("
fi

#Installation de nodejs et npm
if apt install nodejs npm -y; then
    npm install -g pm2 #Installation de PM2 (Prcoess Manager) qui permet de faire tourner le site en permanence et le reboot si besoin
    NODEJS="Node.js installé avec succès :) !"
else
    NODEJS="Une erreur est survenue lors de l'installation de Node.js :("
fi

#Installation de GIT
if apt install git -y; then
    GIT="GIT installé avec succès :) !"
else
    GIT="Une erreur est survenue lors de l'installation de GIT :("
fi

echo "$APACHE"
echo "$PHP"
echo "$MARIADB"
echo "$NODEJS"
echo "$GIT"

a2enmod proxy
a2enmod proxy_http
a2enmod proxy_wstunnel

systemctl restart apache2

#Git clone pour installer le react pour récupérer le site sur le github
cd
git clone https://github.com/aymonier-elias/magistick.git
cd magistick
npm i

#Initialisation des variables de sécuristaion + phpmyadmin pour la bdd
SECURITE=""
PHPMYADMIN=""

if dpkg -l | grep -q mariadb-server; then
    echo "MariaDB est installée ! Sécurisation en cours..."
    systemctl start mariadb

    # Sécurisation avec les commandes SQL officielles MariaDB
    if \
    mysql -e "DROP USER IF EXISTS ''@'localhost';" && \
    mysql -e "DROP USER IF EXISTS ''@'%' ;" && \
    mysql -e "DROP DATABASE IF EXISTS test;" && \
    mysql -e "FLUSH PRIVILEGES;"; then
        SECURITE="Sécurisation de MariaDB effectuée avec succès :) !"
    else
        SECURITE="Une erreur est survenue lors de la sécurisation de MariaDB :("
    fi
    echo "$SECURITE"

    #Automatisation qui évitent l'écran bleu avec les questions quand on installe phpMyAdmin (debconf... sert à pré enregistrer les réponses)
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password $1" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password $1" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password $1" | debconf-set-selections

    if apt install -y phpmyadmin; then
        PHPMYADMIN="phpMyAdmin a été installé :) !"

        # Création de l'utilisateuyr pour l'accès à la base de données via phpMyAdmin
        echo "Création de l'utilisateur MySQL..."
        DB_USER="wp_admin"
        mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '$1';"
        mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'localhost';"
        mysql -e "FLUSH PRIVILEGES;"

    else
        PHPMYADMIN="Une erreur est survenue lors de l'installation de phpMyAdmin :("
    fi
    echo "$PHPMYADMIN"

else
    echo "MariaDB n'est pas installée, installation requise"
fi
a2enmod rewrite
systemctl restart apache2

#Configuration de Apche
echo "Téléchargement des fichiers de configuration Apache2..."
cd /etc/apache2/sites-available

#Récpération des fichiers conf et ssl depuis le github personnel de Inès
wget -O perso-ssl.conf "https://raw.githubusercontent.com/inesldg/Scripts_SAE501/refs/heads/main/perso-ssl.conf"
wget -O perso.conf "https://raw.githubusercontent.com/inesldg/Scripts_SAE501/refs/heads/main/perso.conf"

#Activation des fichiers config de apache
SSL=""
SITE=""
SITE_SSL=""

if a2enmod ssl; then
    SSL="Le module SSL a bien été activé !"
else
    SSL="Une erreur est survenue lors de l'activation du module SSL"
fi
echo "$SSL"

if a2ensite perso.conf; then
    SITE="Le site a bien été configuré ! !"
else
    SITE="Une erreur est survenue lors de la configuration du site"
fi
echo "$SITE"

if a2ensite perso-ssl.conf; then
    SITE_SSL="Le site est maintenant opérationnel avec le module SSL :) !"
else
    SITE_SSL="La configuration du site en SSL a échoué :("
fi
echo "$SITE_SSL"

systemctl reload apache2

#Installation et préparation de Wordpress
echo "Installation et configuration de WordPress..."
mkdir -p /var/www/html/wordpress
cd /var/www/html/wordpress

#Téléchargement de la dernière version de Wordpress
WORDPRESS=""

if wget https://wordpress.org/latest.tar.gz; then
    tar -xzf latest.tar.gz --strip-components=1 # extrait l'archive et crée un dossier "wordpress"
    rm latest.tar.gz # supprime l'archive téléchargée au début

    WORDPRESS="WordPress téléchargé et extrait avec succès :) !"
else
    WORDPRESS="Une erreur est survenue lors du téléchargement de WordPress :("
fi
echo "$WORDPRESS"

#Création de la base de données pour Wordpress
echo "Création de la base de données..."
mysql -e "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

#Attribution des droits pour le Wordpress
chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress
systemctl restart apache2

#RESTAURATION DU BACKUP DU SITE

#Installation des outils (Cron (planificateur de tâches à toute heure), sshpass, certificat ssl)
#Avec certbot et python3-certbot on génère un vrai certificat ssl et fait la redirection https
apt install -y cron sshpass certbot python3-certbot-apache
echo "Début de la restauration du backup distant..."

#Variables de connexion
BACKUP_USER="" #nom de l'utilisateur du vps qui a le backup
BACKUP_HOST="" #adresse ip du vps qui a le backup
MDP="$1"
BACKUP_BASE="" #dossier qui contient le backup (dans le dossier home et dans un dossier backup_site par ex)
DIRECTION_DESTINATION="/var/www/html/wordpress" #dossier vers lequel le backup ira

#Vérification du mot de passe
if [ -z "$MDP" ]; then
    echo "Erreur : Aucun mot de passe fourni !"
    exit 1
fi

#Détection du dernier backup disponible
echo "Recherche du dernier backup disponible..."
#Script connecté en ssh au vps backup, liste de tout les dossiers triés par ordre crhonologique
#Enregistrement du fichier de backup le plus réçent dans LAST_BACKUP
LAST_BACKUP=$(sshpass -p "$MDP" ssh -o StrictHostKeyChecking=no ${BACKUP_USER}@${BACKUP_HOST} "ls -1 ${BACKUP_BASE} | sort | tail -n 1")

if [ -z "$LAST_BACKUP" ]; then
    echo "Aucun backup trouvé sur le serveur distant :("
else
    BACKUP_DOSSIER="${BACKUP_BASE}/${LAST_BACKUP}"
    echo "Dernier backup détecté : ${LAST_BACKUP}"

    #Restauration des fichiers Wordpress (wp-content etc)
    echo "Restauration des fichiers web..."
    #Mot de passe donné automatiquement, secure copy protocol, source des dossiers + destination, sécurité pour empêcher un crash en cas d'échec de copie
    sshpass -p "$MDP" scp -o StrictHostKeyChecking=no -r ${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DOSSIER}/wp-content ${DIRECTION_DESTINATION}/ 2>/dev/null || true
    sshpass -p "$MDP" scp -o StrictHostKeyChecking=no ${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DOSSIER}/.htaccess ${DIRECTION_DESTINATION}/ 2>/dev/null || true
    sshpass -p "$MDP" scp -o StrictHostKeyChecking=no ${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DOSSIER}/robots.txt ${DIRECTION_DESTINATION}/ 2>/dev/null || true

    #Restauration de la BDD (on cherche un fichier en .sql, en cas de message d'erreur il sera masqué, et si plusieurs .sql on prends le plus récent)
    DB_DUMP=$(sshpass -p "$MDP" ssh -o StrictHostKeyChecking=no ${BACKUP_USER}@${BACKUP_HOST} "ls ${BACKUP_DOSSIER}/*.sql 2>/dev/null | tail -n 1")

    if [ -n "$DB_DUMP" ]; then
        echo "Restauration de la base de données WordPress..."
        #Désigne l'emplacement du fichier temporaire
        sshpass -p "$MDP" scp -o StrictHostKeyChecking=no ${BACKUP_USER}@${BACKUP_HOST}:${DB_DUMP} /tmp/wordpress.sql
        mysql -u wp_admin -p"$MDP" wordpress < /tmp/wordpress.sql # ouvre la session admin wp, cible la bdd restaurée, lit le contenu et exécute les requetes sql dans mariadb
        rm /tmp/wordpress.sql # supprime le fichier temporaire
        echo "Base de données restaurée avec succès :) !"
    else
        echo "Aucun dump SQL trouvé :("
    fi
fi
echo "La restauration a été faite avec succès !"

#Ajustement des permissions Web
chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress

#Création d'un utilisateur SFTP
USER_FTP="admin_ftp"
MDP_FTP="$1"
GROUPE="www-data"
ROOT_SFTP="/var/www"
DOSSIER_SFTP="/var/www/html"
CONFIG_SSHD="/etc/ssh/sshd_config"

#Ajout de l'utilisateur sans dossier perso (-M), on lui attribue un groupe (-g), et on lui enlève le droit d'ouvrir une session ssh (-s pour son shell)
useradd -M -g "$GROUPE" -s /usr/sbin/nologin "$USER_FTP"
echo "${USER_FTP}:${MDP_FTP}" | chpasswd #Applique le mot de passe passé en premier argument

#Configuration du ssh pour le protocole sftp
echo "Configuration du serveur SSH pour SFTP..."

cp "$CONFIG_SSHD" "${CONFIG_SSHD}.bak_$(date +%F_%H-%M-%S)" # faire une copie de la conf ssh au cas où avant de modifier
sed -i 's/^Subsystem\ sftp\ /#Subsystem sftp /' "$CONFIG_SSHD" # déscative (avec un commentaire #) la ligne Subsystem sftp 

#Activation du moteur SFTP (pour pouvoir utiliser le chroot) si jamais il n'a pas été activé (sécurité)
if ! grep -q "Subsystem sftp internal-sftp" "$CONFIG_SSHD"; then
    echo "Subsystem sftp internal-sftp" >> "$CONFIG_SSHD"
fi

#Ajout du bloc Match User à la fin du fichier
cat <<EOF >> "$CONFIG_SSHD"
#Configuration SFTP spécifique à l'utilisateur USER_FTP
Match User $USER_FTP
    ChrootDirectory $ROOT_SFTP
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOF

#Redémrrage du ssh
sshd -t # verif de la syntaxe
if [ $? -eq 0 ]; then # on vérifie si le code de retour est bien 0 (qui signifie aucune erreur)
    systemctl restart ssh
    echo "Service SSH redémarré avec succès :) !"
else
    echo "Une erreur est survenue lors de la configuration SSHD :("
fi

#Ajustement des droits pour le bon fonctionnement du chroot, et pour que l'utilisateur ftp puisse modifier les fihciers du site etc
chown -R root:www-data "$DOSSIER_SFTP"
chmod -R 775 "$DOSSIER_SFTP"

#Activation du vrai certificat SSL pour le HTTPS avec nom de domaine, adresse mail pour alertes, règle de redirection automatique pour http / https
echo "Génération du certificat SSL avec Certbot..."
if certbot --apache \
  -d ip87-106-3-165.pbiaas.com \
  --non-interactive \
  --agree-tos \
  --email ledig.ines@gmail.com \
  --redirect \
  --no-eff-email; then
    echo "Certificat SSL configuré avec succès :) !"
else
    echo "Erreur lors de la génération du certificat SSL avec Certbot :("
fi

#Activation et lancement du service cron
systemctl enable cron
systemctl start cron

#Recherche du script de backup stocké sur un github, le rend exécutable
wget "https://raw.githubusercontent.com/" -O /root/backup.sh #A COMPLETER
chmod +x /root/backup.sh

#Planification de l'exécution de cron : minute 0, heure 3, tout les jours / mois / jours de la semaine
echo "Planification des sauvegardes avec Cron..."
CRON="0 3 * * * /root/backup.sh '$1'"

#Lecture des tâches cron, supp ligne du backup et ajout de la nouvelle à la fin du texte, enregistrement
if ( crontab -l 2>/dev/null | grep -Fv "/root/backup.sh" ; echo "$CRON" ) | crontab - ; then
    echo "La planification des sauvegardes avec Cron a été effectuée avec succès :) !"
else
    echo "Erreur lors de l'enregistrement de la tâche dans la crontab :("
fi

echo "=========================================================="
echo "          RECAPITULATIF DU DEPLOIEMENT DU SERVEUR         "
echo "=========================================================="
echo ""
echo "  [Memoire]        : ${FICHIER_SWAP}"
echo "  [Utilisateur]    : ${USER_VPS}"
echo "  [Serveur Web]    : ${APACHE}"
echo "  [Langage]        : ${PHP}"
echo "  [Base de donnees]: ${MARIADB}"
echo "  [Node.js / PM2]  : ${NODEJS}"
echo "  [Gestionnaire]   : ${GIT}"
echo "  [Securite BDD]   : ${SECURITE}"
echo "  [phpMyAdmin]     : ${PHPMYADMIN}"
echo ""
echo "  ---------------- CONFIGURATION SITE ------------------"
echo "  [Module SSL]     : ${SSL}"
echo "  [VHost HTTP]     : ${SITE}"
echo "  [VHost HTTPS]    : ${SITE_SSL}"
echo "  [WordPress]      : ${WORDPRESS}"
echo "  [Dernier Backup] : ${LAST_BACKUP:-Aucun backup restaure}"
echo "  [Accès SFTP]     : Utilisateur ${USER_FTP} (Chroot /var/www)"
echo ""
echo "=========================================================="
echo "      LE DEPLOIEMENT DU SERVEUR EST TERMINE !             "
echo "=========================================================="
echo ""
echo "   LA, LA LA, LA LA, LA LA LA LA LA LA !"
echo "   Le serveur est prêt, il est temps d'aller prendre café !"
echo "=========================================================="
