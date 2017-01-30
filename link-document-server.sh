#!/bin/bash

SERVER_HOST=${SERVER_HOST:-""};
ONLYOFFICE_DIR=${ONLYOFFICE_DIR:-"/var/www/onlyoffice"};
ONLYOFFICE_ROOT_DIR="${ONLYOFFICE_DIR}/WebStudio"
DOCKER_ONLYOFFICE_SUBNET=${DOCKER_ONLYOFFICE_SUBNET:-""};
ONLYOFFICE_MONOSERVE_COUNT=${ONLYOFFICE_MONOSERVE_COUNT:-2};

SYSCONF_TEMPLATES_DIR=${SYSCONF_TEMPLATES_DIR:-"/app/onlyoffice/setup/config"}
DOCUMENT_SERVER_ENABLED=false
DOCUMENT_SERVER_ADDR=${1:-""};
DOCUMENT_SERVER_PROTOCOL=${DOCUMENT_SERVER_PROTOCOL:-"http"};
DOCUMENT_SERVER_API_URL="\/OfficeWeb\/apps\/api\/documents\/api\.js";


if [ ${DOCUMENT_SERVER_HOST} ]; then
        DOCUMENT_SERVER_ENABLED=true;
        DOCUMENT_SERVER_API_URL="${DOCUMENT_SERVER_PROTOCOL}://${DOCUMENT_SERVER_HOST}${DOCUMENT_SERVER_API_URL}";
elif [ ${DOCUMENT_SERVER_ADDR} ]; then
        DOCUMENT_SERVER_ENABLED=true;
        DOCUMENT_SERVER_HOST=${DOCUMENT_SERVER_ADDR};
fi

if [ "${DOCUMENT_SERVER_ENABLED}" == "true" ]; then
        if [ -f ${SYSCONF_TEMPLATES_DIR}/nginx/prepare-onlyoffice ]; then
			sed -e '/{{DOCUMENT_SERVER_HOST_ADDR}}/ s/#//' -i ${SYSCONF_TEMPLATES_DIR}/nginx/prepare-onlyoffice
            sed 's,{{DOCUMENT_SERVER_HOST_ADDR}},'"${DOCUMENT_SERVER_PROTOCOL}:\/\/${DOCUMENT_SERVER_HOST}"',' -i ${SYSCONF_TEMPLATES_DIR}/nginx/prepare-onlyoffice
        fi

        for serverID in $(seq 1 ${ONLYOFFICE_MONOSERVE_COUNT});
        do
                ROOT_DIR=${ONLYOFFICE_ROOT_DIR};
                if [ $serverID != 1 ]; then
                        ROOT_DIR=${ROOT_DIR}$serverID
                fi

                # change web.appsettings link to editor
                sed '/files\.docservice\.url\.converter/s!\(value\s*=\s*\"\)[^\"]*\"!\1'${DOCUMENT_SERVER_PROTOCOL}':\/\/'${DOCUMENT_SERVER_HOST}'\/ConvertService\.ashx\"!' -i  ${ROOT_DIR}/web.appsettings.config
                sed '/files\.docservice\.url\.api/s!\(value\s*=\s*\"\)[^\"]*\"!\1'${DOCUMENT_SERVER_API_URL}'\"!' -i ${ROOT_DIR}/web.appsettings.config
                sed '/files\.docservice\.url\.storage/s!\(value\s*=\s*\"\)[^\"]*\"!\1'${DOCUMENT_SERVER_PROTOCOL}':\/\/'${DOCUMENT_SERVER_HOST}'\/FileUploader\.ashx\"!' -i ${ROOT_DIR}/web.appsettings.config
                sed '/files\.docservice\.url\.command/s!\(value\s*=\s*\"\)[^\"]*\"!\1'${DOCUMENT_SERVER_PROTOCOL}':\/\/'${DOCUMENT_SERVER_HOST}'\/coauthoring\/CommandService\.ashx\"!' -i ${ROOT_DIR}/web.appsettings.config

                if [ -n "${DOCKER_ONLYOFFICE_SUBNET}" ] && [ -n "${SERVER_HOST}" ]; then
                        sed '/files\.docservice\.url\.portal/s!\(value\s*=\s*\"\)[^\"]*\"!\1http:\/\/'${SERVER_HOST}'\"!' -i ${ROOT_DIR}/web.appsettings.config
                fi

                if ! grep -q "files\.docservice\.url\.command" ${ROOT_DIR}/web.appsettings.config; then
          sed '/files\.docservice\.url\.storage/a <add key=\"files\.docservice\.url\.command\" value=\"'${DOCUMENT_SERVER_PROTOCOL}':\/\/'${DOCUMENT_SERVER_HOST}'\/coauthoring\/CommandService\.ashx\" \/>/' -i ${ROOT_DIR}/web.appsettings.config
                else
          sed '/files\.docservice\.url\.command/s!\(value\s*=\s*\"\)[^\"]*\"!\1'${DOCUMENT_SERVER_PROTOCOL}':\/\/'${DOCUMENT_SERVER_HOST}'\/coauthoring\/CommandService\.ashx\"!' -i ${ROOT_DIR}/web.appsettings.config
                fi
        done

        RedisData="\"converter\":\"${DOCUMENT_SERVER_PROTOCOL}://${DOCUMENT_SERVER_HOST}/ConvertService.ashx\"";
        RedisData="${RedisData},\"api\":\"/OfficeWeb/apps/api/documents/api.js\"";
        RedisData="${RedisData},\"storage\":\"${DOCUMENT_SERVER_PROTOCOL}://${DOCUMENT_SERVER_HOST}/FileUploader.ashx\"";
        RedisData="${RedisData},\"command\":\"${DOCUMENT_SERVER_PROTOCOL}://${DOCUMENT_SERVER_HOST}/coauthoring/CommandService.ashx\"";

        if [ -n "${DOCKER_ONLYOFFICE_SUBNET}" ] && [ -n "${SERVER_HOST}" ]; then
                RedisData="${RedisData},\"portal\":\"http://${SERVER_HOST}\"";
		fi

    redis-cli  PUBLISH asc:channel:ASC.Web.Core.Files.DocServiceUrl "{\"CacheId\":\"140ab4e4-17d0-47dd-ba64-91f09bf20a72\",\"Object\":{\"Data\":{$RedisData}},\"Action\":7}"
else
 if [ -f ${SYSCONF_TEMPLATES_DIR}/nginx/prepare-onlyoffice ]; then
	sed -e '/{{DOCUMENT_SERVER_HOST_ADDR}}/ s/^#*/#/' -i /app/onlyoffice/setup/config/nginx/onlyoffice
 fi
fi
