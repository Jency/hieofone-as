#!/bin/bash
set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

file_env DB_PASSWORD
file_env APP_KEY
file_env APP_URL
file_env MAILGUN_DOMAIN
file_env MAILGUN_SECRET
file_env ASSET_URL
file_env PUBKEY
file_env PRIVKEY
maxTries=60
while [ "$maxTries" -gt 0 ] && ! /usr/bin/mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "show  databases;"; do
  let maxTries--
  sleep 1
done
echo
if [ "$maxTries" -le 0 ]; then
  echo >&2 "error: unable to contact MariaDB after $maxTries tries"
  exit 1
fi
if [ $(/usr/bin/mysql -N  -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e \
    "select count(*) from information_schema.tables where \
        table_schema='$DB_DATABASE' and table_name='migrations';") -eq 1 ]; then
    echo >&2 'migrations database already created'
else
    php artisan migrate:install
fi
php artisan migrate
php artisan storage:link
if ! [ -z "$SYNCTHING_HOST" ]; then
	maxTries1=60
	while [ "$maxTries1" -gt 0 ] && ! [ -f /var/syncthing/config/config.xml ]; do
	  let maxTries1--
	  sleep 1
	done
	echo
	if [ "$maxTries1" -le 0 ]; then
	  echo >&2 "error: unable to contact Syncthing after $maxTries1 tries"
	  exit 1
	fi
	SYNCTHING_APIKEY=$(cat /var/syncthing/config/config.xml | awk -F "[><]" '/apikey/{print $3}')
	export "SYNCTHING_APIKEY"=$SYNCTHING_APIKEY
fi
exec "$@"
