#!/usr/bin/env sh
#
# Ping Identity DevOps - Docker Build Hooks
#
#- This hook is called when the container has been built in a prior startup
#- and a configuration has been found.
#
${VERBOSE} && set -x

# shellcheck source=../../../../pingcommon/opt/staging/hooks/pingcommon.lib.sh
. "${HOOKS_DIR}/pingcommon.lib.sh"

# shellcheck source=../../../../pingdatacommon/opt/staging/hooks/pingdata.lib.sh
. "${HOOKS_DIR}/pingdata.lib.sh"

echo "Restarting container"

# if this hook is provided it can be executed early on
run_hook "21-update-server-profile.sh"

certificateOptions=$( getCertificateOptions )
_returnCode=${?}
if test ${_returnCode} -ne 0 ; then
    echo_red "${certificateOptions}"
    container_failure 183 "Invalid certificate options"
fi


#
# If we are RESTARTing the server, we will need to copy any
# keystore/truststore certificate and pin files to the
# pd.profile if they aren't already set.  This implies that
# the server used those keystore/trustore files initially to
# setup the server

# on-setup ---- generate-certificate ==> /opt/out/instance/config/keystore

# on-restart
# 1. Do they have a CERT_FILE defined?
#    - yes conintue
#    - no --> CERT_FILE=/opt/out/instance/config/keystore
# 2. Is there a CERT in that location?
#    - yes
#       - does ${SECRETS_DIR}/file exists? (came in through vault or secrets management)
#       - yes - do nothing
#       - no  - cp CERT_FILE --> ${SECRETS_DIR}/file
#    - no
echo "Copying existing certificate files from existing install..."
for _certFile in keystore keystore.p12 truststore truststore.p12 ; do
    if test -f "${SERVER_ROOT_DIR}/config/${_certFile}" -a ! -f "${PD_PROFILE}/server-root/pre-setup/config/${_certFile}" ; then
        echo "  ${SERVER_ROOT_DIR}/config/${_certFile} ==>"
        echo "    ${PD_PROFILE}/server-root/pre-setup/config/${_certFile}"

        cp -af "${SERVER_ROOT_DIR}/config/${_certFile}" \
           "${PD_PROFILE}/server-root/pre-setup/config/${_certFile}"
    else
        echo "  ${_certFile} not found in existing install or was found in pd.profile"
    fi
done

echo "Copying existing certificate pin files from existing install..."
for _pinFile in keystore.pin truststore.pin ; do
    if test -f "${SERVER_ROOT_DIR}/config/${_pinFile}" -a ! -f "${PD_PROFILE}/server-root/pre-setup/config/${_pinFile}" ; then
        echo "  ${SERVER_ROOT_DIR}/config/${_pinFile} ==>"
        echo "    ${PD_PROFILE}/server-root/pre-setup/config/${_pinFile}"

        "${SERVER_ROOT_DIR}"/bin/encrypt-file --decrypt \
            --input-file "${SERVER_ROOT_DIR}/config/${_pinFile}" \
            --output-file "${PD_PROFILE}/server-root/pre-setup/config/${_pinFile}"
    else
        echo "  ${_pinFile} not found in existing install or was found in pd.profile"
    fi
done


# echo "  ${SERVER_ROOT_DIR}/config/encryption-settings.pin ==>"
# echo "    ${PD_PROFILE}/server-root/pre-setup/config/encryption-settings.pin"
# cp -af "${SERVER_ROOT_DIR}/config/encryption-settings.pin" \
#   "${PD_PROFILE}/server-root/pre-setup/config/encryption-settings.pin"


# echo "  ${SERVER_ROOT_DIR}/config/encryption-settings ==>"
# echo "    ${PD_PROFILE}/server-root/pre-setup/config/encryption-settings"
# cp -af "${SERVER_ROOT_DIR}/config/encryption-settings" \
#   "${PD_PROFILE}/server-root/pre-setup/config/encryption-settings"

encryptionOption=$( getEncryptionOption )
_returnCode=${?}
if test ${_returnCode} -ne 0 ; then
    echo_red "${encryptionOption}"
    container_failure 183 "Invalid encryption option"
fi

jvmOptions=$( getJvmOptions )
_returnCode=${?}
if test ${_returnCode} -ne 0 ; then
    echo_red "${jvmOptions}"
    container_failure 183 "Invalid JVM options"
fi

export certificateOptions encryptionOption jvmOptions

echo "Checking license file..."
_currentLicense="${LICENSE_DIR}/${LICENSE_FILE_NAME}"
_pdProfileLicense="${PD_PROFILE}/server-root/pre-setup/${LICENSE_FILE_NAME}"
if test ! -f "${_pdProfileLicense}" ; then
    echo "Copying in license from existing install."
    echo "  ${_currentLicense} ==> "
    echo "    ${_pdProfileLicense}"
    cp -af "${_currentLicense}" "${_pdProfileLicense}"
fi

# If the a setup-arguments.txt file isn't found, then generate
if test ! -f "${_setupArgumentsFile}"; then
    generateSetupArguments
fi

# Copy the manage-profile.log to a previous version to keep size down due to repeated fail attempts
mv "${SERVER_ROOT_DIR}/logs/tools/manage-profile.log" "${SERVER_ROOT_DIR}/logs/tools/manage-profile.log.prev"

echo "Merging changes from new server profile..."

"${SERVER_BITS_DIR}"/bin/manage-profile replace-profile \
        --serverRoot "${SERVER_ROOT_DIR}" \
        --profile "${PD_PROFILE}" \
        --useEnvironmentVariables

_manageProfileRC=$?
if test ${_manageProfileRC} -ne 0 ; then
    echo_red "*****"
    echo_red "An error occurred during mange-profile replace-profile."
    echo_red "${SERVER_ROOT_DIR}/logs/tools/manage-profile.log listed below."
    echo_red "*****"

    cat "${SERVER_ROOT_DIR}/logs/tools/manage-profile.log"

    container_failure 20 "Resolve the issues with your server-profile"
fi

