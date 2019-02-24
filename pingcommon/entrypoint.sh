#!/usr/bin/env sh
set -x

# shellcheck source=lib.sh
. "${BASE}/lib.sh"


if test "$1" = "start-server" ; then
    shift

    apply_local_server_profile

    # if a git repo is provided, it has not yet been cloned
    # the only way to provide this hook is via the IN_DIR volume
    # aka "local server-profile"
    # or a previous run of the container that would then checkout
    # hence the name on-restart
    #
    run_if present "${HOOKS_DIR}/00-on-restart.sh"

    if ! test -d "${SERVER_ROOT_DIR}" ; then
        ## FIRST TIME EXECUTION OF THE CONTAINER
        run_if present "${HOOKS_DIR}/10-first-time-sequence.sh"
    else
        ## RESTART
        run_if present "${BASE}/19-update-server-profile.sh"
    fi

    run_if present "${HOOKS_DIR}/50-before-post-start.sh"

    run_if present "${HOOKS_DIR}/80-post-start.sh" &

    if ! test -z "${TAIL_LOG_FILES}" ; then
        # shellcheck disable=SC2086
        tail -F ${TAIL_LOG_FILES} 2>/dev/null &
    fi

    if test -z "$*" ; then
        # replace the shell with foreground server
        if test -z "${STARTUP_COMMAND}" ; then
            echo "*** NO CONTAINER STARTUP COMMAND PROVIDED ***"
            exit 90
        else
            exec "${STARTUP_COMMAND}"
        fi
    else
        # start server in the background and execute the provided command (useful for self-test)
        ${STARTUP_COMMAND} &
        exec "$@"
    fi
else
    exec "$@"
fi