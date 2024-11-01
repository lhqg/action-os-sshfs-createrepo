#! /bin/bash

RC=0
WORKDIR=/source

LOCKFILE=${WORKDIR}/.lock

if [ -f ${LOCKFILE} ]
then
  count=0
  waittime=20
  while [ $count -lt 10 -a -f $LOCKFILE ]
  do
    echo "::notice title=CreateRepodata::Lock file found, waiting ${waittime}s"
    sleep $waittime
    count=$((count + 1))
  done
  if [ -f ${LOCKFILE}]
  then
    echo "::error title=CreateRepodata::Lock still present, aborting."
    exit 127
  fi
fi

touch $LOCKFILE

pwd

[ -n "${SFTP_PASSWORD}" ] && echo "${SFTP_PASSWORD}" > ${WORKDIR}/.sftp_password

if [ -r ${WORKDIR}/.sftp_password ]
then
  echo "::notice title=CreateRepodata::SFTP server      is ${SFTP_SERVER}"
  echo "::notice title=CreateRepodata::SFTP user        is ${SFTP_USER}"
  echo "::notice title=CreateRepodata::SFTP remote path is ${SFTP_REMOTE_PATH}"

  # Add SSH key of SFTP server to known hosts
  if [ -n "${SFTP_SERVER_KEY_TYPE}" -a -n "${SFTP_SERVER_KEY_FINGERPRINT}" ]
  then

    mkdir -p ~/.ssh
    chown 0750 ~/.ssh
    echo "${SFTP_SERVER} ${SFTP_SERVER_KEY_TYPE} ${SFTP_SERVER_KEY_FINGERPRINT}" >> ~/.ssh/known_hosts
    chmod 0600 ~/.ssh/known_hosts

    # Mount the SFTP remote path
    YUMREPO_DIR=${WORKDIR}/yumrepo
    mkdir -m 0755 ${YUMREPO_DIR}

    cat ${WORKDIR}/.sftp_password | sshfs ${SFTP_USER}@${SFTP_SERVER}:${SFTP_REMOTE_PATH} ${YUMREPO_DIR}
    RC=$?

    if [ $RC -eq 0 ]
    then
      echo "::notice title=CreateRepodata::Running createrepo for ${SFTP_REMOTE_PATH}"
      createrepo -v ${YUMREPO_DIR}
      RC=$?
    else
      echo "::error title=CreateRepodata::Unable to perform SSHFS mount"
    fi

    fusermount -u ${YUMREPO_DIR}
  else
    echo "::error title=CreateRepodata::No SSH key type or fingerprint."
  fi
else
  echo "::error title=CreateRepodata::Unable to find the SFTP password file under ${WORKDIR}"
fi

rm -f $LOCKFILE

exit $RC