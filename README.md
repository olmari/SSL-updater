# SSL-updater
Scripts and guides to make automated SSL-updating with least possible permissions needed.

# Needs plenty documentation still, first upload :)

Depencies:  
https://github.com/diafygi/acme-tiny (At least Debian has this in their repositories also)  
https://github.com/zakjan/cert-chain-resolver  

Idea is that ssl-updater.sh per certificate is run as daily cronjob and it will check need for renewing SSL-certificate and update it as neccesary, all while machine permissions is kept to absolute minimum. only ssl-updater needs Lets encrypt account key, only www-data needs certificate key (apart human user when issuing certificate signing request file once), and so on.

## ssl-updater.sh usage:
Run daily as cron job, can be run manually. Takes one optional parameter, "force", to attempt certificate renewal instantly.

## sha512passwd.sh usage:
Generates crypt()-compatible SHA-512 ($6$) passwords with maximum length salt.
Usage: sha512passwd USER [PASS]                                          

## To-do:
 - Document system group addition, so www-data and script can share needed file permissions
 - Explain file structure and permissioning for certificates and related files under /var/www/
 - Nginx (minimum) examples
 - Document visudo example so that ssl-updater script has power to restart Nginx and only that