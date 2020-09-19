#!/bin/bash

# Generates crypt()-compatible SHA-512 ($6$) passwords with maximum length
# salt.
#
# Copyright (C) 2020 Sami Olmari, Oy Olmari Ab
# Original script made someone from Kapsi ry with verbal permission
# to do whatever, do contact me for proper credentials!
#
# This software is licensed under GPL2, see LICENSE

# Usage: sha512passwd USER [PASS]                                          
# salt. Returns .htpasswd format.                                          

# EXAMPLE                                                                  
# sha512passwd joedoe >> .htaccess                                         

############################################################################

# die RETVAL [MESSAGE]
die() { [ ! -z "$2" ] && echo "$2" >&2; exit $1; }

# check for required programs
for i in perl base64; do
	if ! which $i &> /dev/null; then
		err="$err \"$i\""
	fi
done
[[ $err ]] && die 2 "Didn't find following program(s):$err, exiting."

# check for 1-2 parameters
[[ $# -lt 1 || $# -gt 2 ]] && die 1 "Usage: $0 USER [PASS]"

# if pass not provided, ask for it
if [ -z "$2" ]; then
	read -s -p "Password: " pass; echo >&2
	read -s -p "Confirm: " pass2; echo >&2
	[ "$pass" != "$pass2" ] && die 3 "Passwords doesn't match, exiting."
else
	pass="$2"
fi

user="$1"

# get salt
salt=$(base64 /dev/urandom | head -c 16)

# generate pass
perl -E "print '$user:' . crypt('$pass', '\$6\$' . '$salt') . \"\n\";"
