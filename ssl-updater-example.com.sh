#!/bin/bash

# Bash-script for automating checking and renewing of SSL-certificates, the least permissions needed -way
#
# Copyright (C) 2020 Sami Olmari, Oy Olmari Ab
#
# This software is licensed under GPL2, see LICENSE

# User defined variables
SSL_DIR="/var/www/.ssl/example.com"            # Directory where certificates etc resides.
ACME_DIR="/var/www/.well-known/acme-challenge" # Directory where acme-challenge token is put.
LE_CONTACT="mailto:contact@example.com"        # Where Lets encrypt sends notifications.
DAYS_TO_EXPIRE=30                              # Renew when cert expires in this many days, or ...
AFTER_DAYS_OLD=30                              # ... renew after cert is this old in days.
TEST_MODE=false                                # When true, use staging server, gives snakeoil, does not ratelimit.

# Global function variables
NOW_EPOCH=$( date +%s )

function check_cli_parameters () {
  if [ -n "$1" ];
  then
    if ! [ "${1^^}" == "FORCE" ];
    then
      echo "Usage: $0 [force]"
      return 1
    fi
    return 0
  fi
}

function check_cert_exist () {
  if [ -e ${SSL_DIR}/chain.pem ];
  then
    return 0
  else
    echo "Certificate file: ${SSL_DIR}/chain.pem does not exist!"
    return 1
  fi
}

function check_cert_startdays () {
  local start_date=$( echo | openssl x509 -inform pem -noout -startdate -in ${SSL_DIR}/chain.pem | cut -d "=" -f 2 )
  local start_epoch=$( date -d "$start_date" +%s )
  local start_days="$(( ($NOW_EPOCH - $start_epoch) / (3600 * 24) ))"
  echo $start_days
}

function check_cert_enddays () {
  local expiry_date=$( echo | openssl x509 -inform pem -noout -enddate -in ${SSL_DIR}/chain.pem | cut -d "=" -f 2 )
  local expiry_epoch=$( date -d "$expiry_date" +%s )
  local expiry_days="$(( ($expiry_epoch - $NOW_EPOCH) / (3600 * 24) ))"
  echo $expiry_days
}

function check_needs_update () {
  if [ "${1^^}" == "FORCE" ];
  then
    echo "Issuing forced renew"
    return 0
  fi
  if [ $(check_cert_enddays) -le $DAYS_TO_EXPIRE ];
  then
    echo "Certificate expires in $DAYS_TO_EXPIRE days, issuing renew"
    return 0
  fi
  if [ $(check_cert_startdays) -ge $AFTER_DAYS_OLD ];
  then
    echo "Certificate is $AFTER_DAYS_OLD days old, issuing renew"
    return 0
  fi
  echo "No need to update"
  return 2
}

function do_cert_update () {
  if [ "${TEST_MODE^^}" == "TRUE" ];
  then
    echo "Running Acme-tiny in test mode"
    python ${HOME}/acme-tiny/acme_tiny.py --directory-url https://acme-staging-v02.api.letsencrypt.org/directory --contact ${LE_CONTACT} --account-key ${HOME_DIR}/account.key --csr ${SSL_DIR}/domain.csr --acme-dir ${ACME_DIR} > ${SSL_DIR}/signed.crt || return 1
  else
    echo "Running Acme-tiny in production mode"
    python ${HOME}/acme-tiny/acme_tiny.py --contact ${LE_CONTACT} --account-key ${HOME}/account.key --csr ${SSL_DIR}/domain.csr --acme-dir ${ACME_DIR} > ${SSL_DIR}/signed.crt || return 1
  fi
}

function build_cert_chains () {
  echo "Copying successfully received certificate into ${SSL_DIR}/chain.pem"
  cat ${SSL_DIR}/signed.crt > ${SSL_DIR}/chain.pem
  echo "Running Cert-chain-resolver"
  ${HOME}/cert-chain-resolver/cert-chain-resolver --include-system --intermediate-only --output ${SSL_DIR}/fullchain.pem ${SSL_DIR}/chain.pem || return 1
}

function reload-webserver () {
  echo "Restarting webserver"
  sudo /bin/systemctl restart nginx.service || { echo "Failed to restart webserver!"; return 1; }
}

# Main program
check_cli_parameters $1 || exit 1
echo "$(date -Iminutes)"
check_cert_exist || exit 1
check_needs_update $1 || exit 0
do_cert_update || exit 1
build_cert_chains || exit 1
reload-webserver || exit 1
echo "Finished"
