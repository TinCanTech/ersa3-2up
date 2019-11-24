#!/bin/sh

set -e

fail_upgrade ()
{
	# Replace die()
	printf "\n\n%s\n" "$1"

	# Delete new temp dirs and files becuase the originals still exist
	[ -d "$EASYRSA_NEW_PKI" ] && rm -rf "$EASYRSA_NEW_PKI"
	[ -d "$EASYRSA_SAFE_PKI" ] && rm -rf "$EASYRSA_SAFE_PKI"

	exit
}

verify_new_pki ()
{
	printf "%s" "> Verify default NEW PKI does not exist .."
	EASYRSA_NEW_PKI="$EASYRSA/pki"
	[ -d "$EASYRSA_NEW_PKI" ] && fail_upgrade "Cannot over write destination PKI: $EASYRSA_NEW_PKI"
	printf "%s\n" " OK"

	printf "%s" "> Verify VERY-SAFE-PKI does not exist .."
	EASYRSA_SAFE_PKI="$EASYRSA/VERY-SAFE-PKI"
	[ -d "$EASYRSA_SAFE_PKI" ] && fail_upgrade "Cannot over write destination PKI: $EASYRSA_SAFE_PKI"
	printf "%s\n" " OK"
}

verify_current_pki ()
{
	printf "%s" "> Find current PKI .."

	[ -f "$EASYRSA_VER2_VARSFILE" ] || fail_upgrade "Cannot find current current vars file: $EASYRSA_VER2_VARSFILE"

	# shellcheck source=/dev/null
	. "$EASYRSA_VER2_VARSFILE" 1> /dev/null

	[ -d "$KEY_DIR" ] || fail_upgrade "Cannot find current current PKI: $KEY_DIR"

	printf "%s\n" " OK"
}

verify_current_ca ()
{
	printf "%s" "> Find CA .."
	[ -f "$KEY_DIR/ca.crt" ] || fail_upgrade "Cannot find current current ca.crt file: $KEY_DIR/ca.crt"
	printf "%s\n" " OK"
	printf "%s\n" "> Found CA at: $KEY_DIR/ca.crt"

	# Will require confirm() from easyrsa
		printf "%s\n" ""
		printf "%s\n" "***** Confirm files -- Requires user input *****"
		printf "%s\n" ""
}

backup_current_pki ()
{
	printf "%s" "> Backup old PKI .."

	mkdir $EASYRSA_VERBOSE -p "$EASYRSA_SAFE_PKI" \
		|| fail_upgrade "Failed to create safe PKI dir: $EASYRSA_SAFE_PKI"

	cp $EASYRSA_UPGRADE_VERBOSE -r "$KEY_DIR" "$EASYRSA_SAFE_PKI" \
		|| fail_upgrade "Failed to copy $KEY_DIR to $EASYRSA_SAFE_PKI"

	cp $EASYRSA_VERBOSE "$EASYRSA_VER2_VARSFILE" "$EASYRSA_SAFE_PKI" \
		|| fail_upgrade "Failed to copy $EASYRSA_VER2_VARSFILE to EASYRSA_SAFE_PKI"

	printf "%s\n" " OK"
}


create_new_pki ()
{
	printf "%s" "> Create NEW PKI dirs .."
	for i in private reqs issued certs_by_serial; do
		mkdir $EASYRSA_VERBOSE -p "$EASYRSA_PKI/$i" || fail_upgrade "Failed to create PKI dir: $EASYRSA_PKI/$i"
	done
	printf "%s\n" " OK"

	printf "%s" "> Copy database to NEW PKI .."
	for i in index.txt index.txt.attr index.txt.old serial serial.old ca.crt; do
		cp $EASYRSA_VERBOSE "$KEY_DIR/$i" "$EASYRSA_PKI" || fail_upgrade "Failed to copy $KEY_DIR/$i to $EASYRSA_PKI"
	done
	printf "%s\n" "  OK"

	printf "%s" "* Copy .csr .pem .crt .key files to NEW PKI .."
	cp $EASYRSA_VERBOSE "$KEY_DIR/"*".csr" "$EASYRSA_PKI/reqs" || fail_upgrade "Failed to copy .csr"
	cp $EASYRSA_VERBOSE "$KEY_DIR/"*".pem" "$EASYRSA_PKI/certs_by_serial" || fail_upgrade "Failed to copy .pem"
	cp $EASYRSA_VERBOSE "$KEY_DIR/"*".crt" "$EASYRSA_PKI/issued" || fail_upgrade "Failed to copy .crt"
	cp $EASYRSA_VERBOSE "$KEY_DIR/"*".key" "$EASYRSA_PKI/private" || fail_upgrade "Failed to copy .key"
	# Todo: CRL - Or generate a new CSR on completion
	printf "%s\n" "  OK"
}

build_v3_vars ()
{
	printf "%s" "* Build v3 vars file .."

	EASYRSA_EXT="easyrsa-upgrade-23" #"$(date +%s%N)"
	EASYRSA_VARSV2_TMP="$EASYRSA/vars-v2.tmp.$EASYRSA_EXT"
	[ -f "$EASYRSA_VARSV2_TMP" ] && rm "$EASYRSA_VARSV2_TMP"
	EASYRSA_VARSV3_TMP="$EASYRSA/vars-v3.tmp.$EASYRSA_EXT"
	[ -f "$EASYRSA_VARSV3_TMP" ] && rm "$EASYRSA_VARSV3_TMP"
	EASYRSA_VARSV3_NEW="$EASYRSA/vars-v3.new.$EASYRSA_EXT"
	[ -f "$EASYRSA_VARSV3_NEW" ] && rm "$EASYRSA_VARSV3_NEW"
	EASYRSA_VARSV3_WRN="$EASYRSA/vars-v3.wrn.$EASYRSA_EXT"
	[ -f "$EASYRSA_VARSV3_WRN" ] && rm "$EASYRSA_VARSV3_WRN"

	printf "%s\n" "\
########################++++++++++#########################
###                                                     ###
###  WARNING: THIS FILE WAS AUTOMATICALLY GENERATED     ###
###           ALL SETTINGS ARE AT THE END OF THE FILE   ###
###                                                     ###
########################++++++++++#########################

" > "$EASYRSA_VARSV3_WRN" || fail_upgrade "Failed to create $EASYRSA_VARSV3_WRN"

	# May need to find this file
	EASYRSA_VARSV3_EXMP="$EASYRSA/vars.example"
	[ -f "$EASYRSA_VARSV3_EXMP" ] || fail_upgrade "Failed to find $EASYRSA_VARSV3_EXMP"

	grep -vE '^#|^$|^printf "%s\n"' "$EASYRSA_VER2_VARSFILE" > "$EASYRSA_VARSV2_TMP" \
		|| fail_upgrade "Failed to create $EASYRSA_VARSV2_TMP"

	# shellcheck disable=SC2016
	{
		grep 'KEY_SIZE='  "$EASYRSA_VARSV2_TMP" | sed 's`export KEY_SIZE=`set_var EASYRSA_KEY_SIZE `g'
		printf "%s\n" 'set_var EASYRSA_DN "org"'
		grep '_COUNTRY='  "$EASYRSA_VARSV2_TMP" | sed 's`export KEY`set_var EASYRSA_REQ`g'
		grep '_PROVINCE=' "$EASYRSA_VARSV2_TMP" | sed 's`export KEY`set_var EASYRSA_REQ`g'
		grep '_CITY='     "$EASYRSA_VARSV2_TMP" | sed 's`export KEY`set_var EASYRSA_REQ`g'
		grep '_ORG='      "$EASYRSA_VARSV2_TMP" | sed 's`export KEY`set_var EASYRSA_REQ`g'
		grep '_EMAIL='    "$EASYRSA_VARSV2_TMP" | sed 's`export KEY`set_var EASYRSA_REQ`g'
		grep '_OU='       "$EASYRSA_VARSV2_TMP" | sed 's`export KEY`set_var EASYRSA_REQ`g'
		printf "%s\n" 'set_var EASYRSA_NS_SUPPORT "yes"'
	} > "$EASYRSA_VARSV3_TMP" || fail_upgrade "Failed to create $EASYRSA_VARSV3_TMP"

	# shellcheck disable=SC2016
	sed -i 's`\="`\ "`g' "$EASYRSA_VARSV3_TMP"

	cat "$EASYRSA_VARSV3_WRN" "$EASYRSA_VARSV3_EXMP" "$EASYRSA_VARSV3_TMP" > "$EASYRSA_VARSV3_NEW" \
		|| fail_upgrade "Failed to create $EASYRSA_VARSV3_NEW"

	rm -f "$EASYRSA_VARSV3_WRN" "$EASYRSA_VARSV3_TMP"


	# Move/cp old vars to Safe PKI
	# This was specifically done by backup above
	#cp "$EASYRSA_VER2_VARSFILE" "$EASYRSA_SAFE_PKI" || fail_upgrade "Failed to copy OLD vars to $EASYRSA_SAFE_PKI"

	# backup this file for debug
	# this is just a short cut and must be removed
	cp $EASYRSA_VERBOSE "$EASYRSA_VER2_VARSFILE" "$EASYRSA/vars.222.livebackup"

	# Move/cp vars-v3.new to vars
	cp $EASYRSA_VERBOSE "$EASYRSA_VARSV3_NEW" "$EASYRSA_VER2_VARSFILE" \
		|| fail_upgrade "Failed to copy $EASYRSA_VARSV3_NEW to $EASYRSA_VER2_VARSFILE"

	[ -f "$EASYRSA_VARSV2_TMP" ] && rm "$EASYRSA_VARSV2_TMP"
	[ -f "$EASYRSA_VARSV3_TMP" ] && rm "$EASYRSA_VARSV3_TMP"
	[ -f "$EASYRSA_VARSV3_NEW" ] && rm "$EASYRSA_VARSV3_NEW"
	[ -f "$EASYRSA_VARSV3_WRN" ] && rm "$EASYRSA_VARSV3_WRN"

	printf "%s\n" "  OK"
}

create_openssl_cnf ()
{
	printf "%s" "* OpenSSL config .."
			# chicken and egg again ..
			EASYRSA_SSL_CNFFILE="$EASYRSA/openssl-easyrsa.cnf"
			EASYRSA_PKI_SSL_CNFFILE="$EASYRSA/pki/openssl-easyrsa.cnf"
			[ -f "$EASYRSA_SSL_CNFFILE" ] || fail_upgrade "Failed to find $EASYRSA_SSL_CNFFILE"
			cp "$EASYRSA_SSL_CNFFILE" "$EASYRSA_PKI_SSL_CNFFILE" || fail_upgrade "Failed egg01"
	printf "%s\n" "  OK"
}

move_easyrsa2_programs ()
{
	# These files may not exist here
	#printf "%s\n" ""
	printf "%s" "* Move easyrsa2 programs to SAFE PKI .."
	for i in build-ca build-dh build-inter build-key build-key-pass build-key-pkcs12 \
		build-key-server build-req build-req-pass clean-all inherit-inter list-crl \
		openssl-0.9.6.cnf openssl-0.9.8.cnf openssl-1.0.0.cnf openssl.cnf pkitool \
		revoke-full sign-req whichopensslcnf; do

		if [ -f "$EASYRSA/$i" ]; then
			cp $EASYRSA_VERBOSE "$EASYRSA/$i" "$EASYRSA_SAFE_PKI" \
				|| fail_upgrade "Failed to copy $EASYRSA/$i $EASYRSA_SAFE_PKI"
			# rm $EASYRSA_VERBOSE -f "$EASYRSA/$i"
		else
			printf "%s\n" "File does not exist, ignoring: $i"
		fi
	done
	printf "%s\n" "  OK"
}


#######################################
# THIS WILL BECOME A FUNCTION: upgrade_23 ()


# Unux: ./vars / Windows: ./vars.bat
EASYRSA_VER2_VARSFILE="$1"
# Windows ... urgh ...

# Verbose for testing
EASYRSA_UPGRADE_VERBOSE=
#EASYRSA_UPGRADE_VERBOSE="-v"

printf "%s\n" "Begin upgrade process .."

verify_new_pki
verify_current_pki
verify_current_ca
backup_current_pki
create_new_pki
build_v3_vars
create_openssl_cnf
move_easyrsa2_programs


printf "%s\n" "upgrade process completed successfully"

printf "%s\n" "\

* NOTICE *

Your settings and PKI have been successfully upgraded to EasyRSA version 3

A backup of your current PKI is here:
- $EASYRSA_SAFE_PKI

To verify the upgrade has completed use command: 'easyrsa show-ca'

WARNING: DO *NOT* USE easyrsa init-pki or your new PKI will be deleted.

EasyRSA upgrade has successfully completed."


if [ "$NOSAVE" -eq 1 ] && [ -d "$EASYRSA_NEW_PKI" ] && [ -d "$EASYRSA_SAFE_PKI" ]; then
	cp $EASYRSA_VERBOSE "$EASYRSA/vars.222.livebackup" "$EASYRSA_VER2_VARSFILE"
	rm -rf "$EASYRSA_NEW_PKI"
	rm -rf "$EASYRSA_SAFE_PKI"
	printf "\n%s\n" "     ***** WARNING: UPGRADE 23 dirs DELETED, v2 vars restored and v3 vars over written *****"
fi

exit 0

