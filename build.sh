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

if [ -n "${INPUT_SFTP_PASSWORD}" ]
then
  echo "::notice title=CreateRepodata::Using SFTP password from input paramaters"
  echo "${INPUT_SFTP_PASSWORD}" > ${WORKDIR}/.sftp_password
fi

if [ -r ${WORKDIR}/.sftp_password -a -s ${WORKDIR}/.sftp_password ]
then
  echo "::notice title=CreateRepodata::SFTP server      is ${INPUT_SFTP_SERVER}"
  echo "::notice title=CreateRepodata::SFTP user        is ${INPUT_SFTP_USER}"
  echo "::notice title=CreateRepodata::SFTP remote path is ${INPUT_SFTP_REMOTE_PATH}"

  # Add SSH key of SFTP server to known hosts
  if [ -n "${INPUT_SFTP_SERVER_KEY_TYPE}" -a -n "${INPUT_SFTP_SERVER_KEY_FINGERPRINT}" ]
  then

    mkdir -p ~/.ssh
    chown 0750 ~/.ssh
    echo "::notice title=CreateRepodata::Adding SSH host key to known hosts"
    echo "${INPUT_SFTP_SERVER} ${INPUT_SFTP_SERVER_KEY_TYPE} ${INPUT_SFTP_SERVER_KEY_FINGERPRINT}" >> ~/.ssh/known_hosts
    chmod 0600 ~/.ssh/known_hosts

    # Mount the SFTP remote path
    YUMREPO_DIR=${WORKDIR}/yumrepo
    mkdir -m 0755 ${YUMREPO_DIR}

    echo "::notice title=CreateRepodata::Trying to perform mount on ${YUMREPO_DIR}"
    cat ${WORKDIR}/.sftp_password | sshfs -o password_stdin ${INPUT_SFTP_USER}@${INPUT_SFTP_SERVER}:${INPUT_SFTP_REMOTE_PATH} ${YUMREPO_DIR}
    RC=$?

    if [ $RC -eq 0 ]
    then
      echo "::notice title=CreateRepodata::Running createrepo for ${INPUT_SFTP_REMOTE_PATH}"
      createrepo -v ${YUMREPO_DIR}
      RC=$?
    else
      echo "::error title=CreateRepodata::Unable to perform SSHFS mount"
    fi

    cd ${WORKDIR}
    fusermount -u ${YUMREPO_DIR} > /dev/null 2>&1
  else
    echo "::error title=CreateRepodata::No SSH key type or fingerprint."
  fi
else
  echo "::error title=CreateRepodata::Unable to find the SFTP password file under ${WORKDIR}"
fi

rm -f $LOCKFILE

exit $RC