#!/bin/bash

ONLYOFFICE_DIR=${ONLYOFFICE_DIR:-"/var/www/onlyoffice"};
ONLYOFFICE_ROOT_DIR="${ONLYOFFICE_DIR}/WebStudio"

MAIL_SERVER_API_PORT=${MAIL_SERVER_API_PORT:-${MAIL_SERVER_PORT_8081_TCP_PORT:-8081}};
MAIL_SERVER_API_HOST=${MAIL_SERVER_API_HOST:-${MAIL_SERVER_PORT_8081_TCP_ADDR}};
MAIL_SERVER_DB_HOST=${1:-${MAIL_SERVER_PORT_3306_TCP_ADDR}};
MAIL_SERVER_DB_PORT=${MAIL_SERVER_DB_PORT:-${MAIL_SERVER_PORT_3306_TCP_PORT:-3306}};
MAIL_SERVER_DB_NAME=${MAIL_SERVER_DB_NAME:-"onlyoffice_mailserver"};
MAIL_SERVER_DB_USER=${MAIL_SERVER_DB_USER:-"mail_admin"};
MAIL_SERVER_DB_PASS=${MAIL_SERVER_DB_PASS:-"Isadmin123"};

MYSQL_SERVER_HOST=${MYSQL_SERVER_HOST:-"localhost"}
MYSQL_SERVER_PORT=${MYSQL_SERVER_PORT:-"3306"}
MYSQL_SERVER_DB_NAME=${MYSQL_SERVER_DB_NAME:-"onlyoffice"}
MYSQL_SERVER_USER=${MYSQL_SERVER_USER:-"root"}
MYSQL_SERVER_PASS=${MYSQL_SERVER_PASS:-""}
MYSQL_SERVER_EXTERNAL=false;

mysql_scalar_exec(){
	local queryResult="";

	if [ "$2" == "opt_ignore_db_name" ]; then
		queryResult=$(mysql --silent --skip-column-names -h ${MYSQL_SERVER_HOST} -P ${MYSQL_SERVER_PORT} -u ${MYSQL_SERVER_USER} --password=${MYSQL_SERVER_PASS} -e "$1");
	else
		queryResult=$(mysql --silent --skip-column-names -h ${MYSQL_SERVER_HOST} -P ${MYSQL_SERVER_PORT} -u ${MYSQL_SERVER_USER} --password=${MYSQL_SERVER_PASS} -D ${MYSQL_SERVER_DB_NAME} -e "$1");
	fi
	echo $queryResult;
}


if [ ${MAIL_SERVER_DB_HOST} ]; then
	MAIL_SERVER_ENABLED=true;

	if [ -z "${MAIL_SERVER_API_HOST}" ]; then
	        if [[ $MAIL_SERVER_DB_HOST =~ $VALID_IP_ADDRESS_REGEX ]]; then
			MAIL_SERVER_API_HOST=${MAIL_SERVER_DB_HOST};
        	elif [[ $EXTERNAL_IP =~ $VALID_IP_ADDRESS_REGEX ]]; then
			MAIL_SERVER_API_HOST=${EXTERNAL_IP};
	   	else
		    echo "MAIL_SERVER_API_HOST is empty";
	            exit 502;
       		fi
	fi
fi

if [ "${MAIL_SERVER_ENABLED}" == "true" ]; then

    timeout=120;
    interval=10;

    while [ "$interval" -lt "$timeout" ] ; do
        interval=$((${interval} + 10));

        MAIL_SERVER_HOSTNAME=$(mysql --silent --skip-column-names -h ${MAIL_SERVER_DB_HOST} \
            --port=${MAIL_SERVER_DB_PORT} -u "${MAIL_SERVER_DB_USER}" \
            --password="${MAIL_SERVER_DB_PASS}" -D "${MAIL_SERVER_DB_NAME}" -e "SELECT Comment from greylisting_whitelist where Source='SenderIP:${MAIL_SERVER_API_HOST}' limit 1;");
        if [[ "$?" -eq "0" ]]; then
            break;
        fi
        
	sleep 10;

	if [ ${LOG_DEBUG} ]; then
		echo "waiting MAIL SERVER DB...";
	fi

    done

    # change web.appsettings
    sed -r '/web\.hide-settings/s/,AdministrationPage//' -i ${ONLYOFFICE_ROOT_DIR}/web.appsettings.config

    MYSQL_MAIL_SERVER_ID=$(mysql_scalar_exec "select id from mail_server_server where mx_record='${MAIL_SERVER_HOSTNAME}' limit 1");

    echo "MYSQL mail server id '${MYSQL_MAIL_SERVER_ID}'";
    if [ -z ${MYSQL_MAIL_SERVER_ID} ]; then
        
        VALID_IP_ADDRESS_REGEX="^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$";
        if [[ $EXTERNAL_IP =~ $VALID_IP_ADDRESS_REGEX ]]; then
            echo "External ip $EXTERNAL_IP is valid";
        else
            echo "External ip $EXTERNAL_IP is not valid";
            exit 502;
        fi

        mysql --silent --skip-column-names -h ${MAIL_SERVER_DB_HOST} \
            --port=${MAIL_SERVER_DB_PORT} -u "${MAIL_SERVER_DB_USER}" \
            --password="${MAIL_SERVER_DB_PASS}" -D "${MAIL_SERVER_DB_NAME}" \
            -e "INSERT INTO greylisting_whitelist (Source, Comment, Disabled) VALUES (\"SenderIP:${EXTERNAL_IP}\", '', 0);";

        mysql_scalar_exec <<END
        ALTER TABLE mail_server_server CHANGE COLUMN connection_string connection_string TEXT NOT NULL AFTER mx_record;
        ALTER TABLE mail_server_domain ADD COLUMN date_checked DATETIME NOT NULL DEFAULT '1975-01-01 00:00:00' AFTER date_added;
        ALTER TABLE mail_server_domain ADD COLUMN is_verified TINYINT(1) UNSIGNED NOT NULL DEFAULT '0' AFTER date_checked;
END

        id1=$(mysql_scalar_exec "INSERT INTO mail_mailbox_server (id_provider, type, hostname, port, socket_type, username, authentication, is_user_data) VALUES (-1, 'imap', '${MAIL_SERVER_HOSTNAME}', 143, 'STARTTLS', '%EMAILADDRESS%', '', 0);SELECT LAST_INSERT_ID();");
        if [ ${LOG_DEBUG} ]; then
            echo "id1 is '${id1}'";
        fi

        id2=$(mysql_scalar_exec "INSERT INTO mail_mailbox_server (id_provider, type, hostname, port, socket_type, username, authentication, is_user_data) VALUES (-1, 'smtp', '${MAIL_SERVER_HOSTNAME}', 587, 'STARTTLS', '%EMAILADDRESS%', '', 0);SELECT LAST_INSERT_ID();");

        if [ ${LOG_DEBUG} ]; then
            echo "id2 is '${id2}'";
        fi
        
        sed '/mail\.certificate-permit/s/\(value *= *\"\).*\"/\1true\"/' -i  ${ONLYOFFICE_ROOT_DIR}/web.appsettings.config
        sed '/mail\.certificate-permit/s/\(value *= *\"\).*\"/\1true\"/' -i  ${ONLYOFFICE_DIR}/Services/MailAggregator/ASC.Mail.Aggregator.CollectionService.exe.config
    else
        id1=$(mysql_scalar_exec "select imap_settings_id from mail_server_server where mx_record='${MAIL_SERVER_HOSTNAME}' limit 1");
        if [ ${LOG_DEBUG} ]; then
            echo "id1 is '${id1}'";
        fi

        id2=$(mysql_scalar_exec "select smtp_settings_id from mail_server_server where mx_record='${MAIL_SERVER_HOSTNAME}' limit 1");
        if [ ${LOG_DEBUG} ]; then
            echo "id2 is '${id2}'";
        fi

        mysql_scalar_exec <<END
        UPDATE mail_mailbox_server SET id_provider=-1, hostname='${MAIL_SERVER_HOSTNAME}' WHERE id in (${id1}, ${id2});
END
    fi

    interval=10;
    while [ "$interval" -lt "$timeout" ] ; do
        interval=$((${interval} + 10));

        MYSQL_MAIL_SERVER_ACCESS_TOKEN=$(mysql --silent --skip-column-names -h ${MAIL_SERVER_DB_HOST} \
            --port=${MAIL_SERVER_DB_PORT} -u "${MAIL_SERVER_DB_USER}" \
            --password="${MAIL_SERVER_DB_PASS}" -D "${MAIL_SERVER_DB_NAME}" \
            -e "select access_token from api_keys where id=1;");
        if [[ "$?" -eq "0" ]]; then
            break;
        fi
        sleep 10;
    done

    if [ ${LOG_DEBUG} ]; then
        echo "mysql mail server access token is ${MYSQL_MAIL_SERVER_ACCESS_TOKEN}";
    fi

    MAIL_SERVER_API_HOST_ADDRESS=${MAIL_SERVER_API_HOST};
    if [[ $MAIL_SERVER_DB_HOST == "onlyoffice-mail-server" ]]; then
    MAIL_SERVER_API_HOST_ADDRESS=${MAIL_SERVER_DB_HOST};
    fi

    mysql_scalar_exec "DELETE FROM mail_server_server;"
    mysql_scalar_exec "INSERT INTO mail_server_server (mx_record, connection_string, server_type, smtp_settings_id, imap_settings_id) \
                       VALUES ('${MAIL_SERVER_HOSTNAME}', '{\"DbConnection\" : \"Server=${MAIL_SERVER_DB_HOST};Database=${MAIL_SERVER_DB_NAME};User ID=${MAIL_SERVER_DB_USER};Password=${MAIL_SERVER_DB_PASS};Pooling=True;Character Set=utf8;AutoEnlist=false\", \"Api\":{\"Protocol\":\"http\", \"Server\":\"${MAIL_SERVER_API_HOST_ADDRESS}\", \"Port\":\"${MAIL_SERVER_API_PORT}\", \"Version\":\"v1\",\"Token\":\"${MYSQL_MAIL_SERVER_ACCESS_TOKEN}\"}}', 2, '${id2}', '${id1}');"
fi

