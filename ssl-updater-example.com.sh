#!/bin/bash

# Bash-script for automating checking and renewing of SSL-certificates, the least permissions needed -way
#
# Copyright (C) 2024 Sami Olmari, IT-Olmari ry, Hacklab Finland ry
#
# This software is licensed under GPL2, see LICENSE
#
# Usage: ssl-updater-example.com.sh [force]
# Returns status or issue-log (stdout) and new cert files.

##
# User defined variables
##
CONTACT="mailto:techdata@example.com"          # Where ACME CA sends notifications.
DAYS_TO_EXPIRE=30                              # Renew when cert expires in this many days, or ...
AFTER_DAYS_OLD=30                              # ... renew after cert is this old in days.
TEST_MODE=false                                # When true, use staging server, gives snakeoil, does not ratelimit.

##
# User defined constants
##

# ACME endpoints, Should work with all ACME-servers, Lets Encrypt as example
ACME_PRODUCTION_SERVER="https://acme-v02.api.letsencrypt.org/directory"
ACME_TEST_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"

# Certificate and acme-challenge directories
SSL_DIR="/var/www/ssl/example.com"             # Certificate files
ACME_DIR="/var/www/acme-challenges"            # Acme-challenge tokens

# Certificate file names
SIGNED=signed.crt                              # Acme-tiny output on successful order
CHAIN=chain.crt                                # Leaf + intermediate chain for webserver, built from signed.
ROOTCHAIN=rootchain.crt                        # Intermediate + root certificate, built from signed, for validating OSCP-response
CSR=domain.csr                                 # Certificate Sign Request (CSR), generate beforehand
STAPLE=ocsp.staple
ACCOUNTKEY=${HOME}/account.key                 # Account key for ACME CA, generate beforehand

##
# System constants
##

# Command to get current time in unix-time
NOW_EPOCH=$( date +%s )

##
# Program
##

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
  if [ -e ${SSL_DIR}/${CHAIN} ];
  then
    return 0
  else
    echo "Certificate file: ${SSL_DIR}/${CHAIN} does not exist!"
    return 1
  fi
}

function check_cert_startdays () {
  local start_date=$( echo | openssl x509 -inform pem -noout -startdate -in ${SSL_DIR}/${CHAIN} | cut -d "=" -f 2 )
  local start_epoch=$( date -d "$start_date" +%s )
  local start_days="$(( ($NOW_EPOCH - $start_epoch) / (3600 * 24) ))"
  echo $start_days
}

function check_cert_enddays () {
  local expiry_date=$( echo | openssl x509 -inform pem -noout -enddate -in ${SSL_DIR}/${CHAIN} | cut -d "=" -f 2 )
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
    local _DIRECTORY_URL="$ACME_TEST_SERVER"
    local _MODE="test"
  else
    local _DIRECTORY_URL="$ACME_PRODUCTION_SERVER"
    local _MODE="production"
  fi
  echo "Running Acme-tiny against ${_MODE} server"
  acme-tiny --directory-url ${_DIRECTORY_URL} --contact ${CONTACT} --account-key ${ACCOUNTKEY} --csr ${SSL_DIR}/${CSR} --acme-dir ${ACME_DIR} > ${SSL_DIR}/${SIGNED} || return 1
}

function build_cert_chains () {
  echo "Copying successfully received certificate into ${SSL_DIR}/${CHAIN}"
  cat ${SSL_DIR}/${SIGNED} > ${SSL_DIR}/${CHAIN}
  echo "Running Cert-chain-resolver"
  ${HOME}/cert-chain-resolver/cert-chain-resolver --include-system --intermediate-only --output ${SSL_DIR}/${ROOTCHAIN} ${SSL_DIR}/${CHAIN} || return 1
}

function fetch_ocsp_staple () {
  echo "Fetching OCSP staple response"
  openssl ocsp -no_nonce -url $(openssl x509 -noout -ocsp_uri -in ${SSL_DIR}/${CHAIN}) -issuer ${SSL_DIR}/${ROOTCHAIN} -cert ${SSL_DIR}/${CHAIN} -verify_other ${SSL_DIR}/${ROOTCHAIN} -respout ${SSL_DIR}/${STAPLE} || return 1
  reload-webserver || exit 1
}

function reload-webserver () {
  echo "Reloading webserver"
  sudo /bin/systemctl reload nginx.service || { echo "Failed to reload webserver!"; exit 1; }
  echo "Finished"
  exit 0
}

# Main program
check_cli_parameters $1 || exit 1
echo "$(date -Iminutes)"
check_cert_exist || exit 1
check_needs_update $1 || fetch_ocsp_staple
do_cert_update || fetch_ocsp_staple
build_cert_chains || exit 1
fetch_ocsp_staple || exit 1
