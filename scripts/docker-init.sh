#!/bin/bash
# Entrypoint for Ubuntu-based ralphex container
# Adapted from umputun/baseimage /init.sh (uses gosu instead of su-exec)

uid=$(id -u)

if [[ ${uid} -eq 0 ]]; then
    [[ "${INIT_QUIET}" != "1" ]] && echo "init container"

    # set container's time zone
    cp /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime
    echo "${TIME_ZONE}" > /etc/timezone
    [[ "${INIT_QUIET}" != "1" ]] && echo "set timezone ${TIME_ZONE} ($(date))"

    # set UID for user app
    if [[ "${APP_UID}" -ne "1001" ]]; then
        [[ "${INIT_QUIET}" != "1" ]] && echo "set custom APP_UID=${APP_UID}"
        usermod -u "${APP_UID}" app
        groupmod -g "${APP_UID}" app
    else
        [[ "${INIT_QUIET}" != "1" ]] && echo "custom APP_UID not defined, using default uid=1001"
    fi

    # set GID for docker group
    if [[ "${DOCKER_GID}" -ne "999" ]]; then
        [[ "${INIT_QUIET}" != "1" ]] && echo "set custom DOCKER_GID=${DOCKER_GID}"
        existing_group=$(getent group "${DOCKER_GID}" | cut -d: -f1)
        if [[ -n "${existing_group}" && "${existing_group}" != "docker" ]]; then
            [[ "${INIT_QUIET}" != "1" ]] && echo "GID ${DOCKER_GID} used by '${existing_group}', adding app to it"
            usermod -aG "${existing_group}" app
        else
            groupmod -g "${DOCKER_GID}" docker 2>/dev/null || groupadd -g "${DOCKER_GID}" docker
            usermod -aG docker app
        fi
    else
        [[ "${INIT_QUIET}" != "1" ]] && echo "custom DOCKER_GID not defined, using default gid=999"
    fi

    chown -R app:app /srv
    if [[ "${SKIP_HOME_CHOWN}" != "1" ]]; then
        chown -R app:app /home/app
    fi

    # mark /workspace as safe for git (mounted volume has different ownership)
    # use --system so it applies to all users (root sets it, app user reads it)
    git config --system --add safe.directory /workspace
fi

if [[ -f "/srv/init.sh" ]]; then
    [[ "${INIT_QUIET}" != "1" ]] && echo "execute /srv/init.sh"
    chmod +x /srv/init.sh
    /srv/init.sh
    if [[ "$?" -ne "0" ]]; then
        echo "/srv/init.sh failed"
        exit 1
    fi
fi

[[ "${INIT_QUIET}" != "1" ]] && echo execute "$@"
if [[ ${uid} -eq 0 ]]; then
    exec gosu app "$@"
else
    exec "$@"
fi
