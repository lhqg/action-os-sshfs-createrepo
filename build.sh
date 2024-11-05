#! /bin/bash

do_hash() {
    HASH_NAME=$1
    HASH_CMD=$2
    echo "${HASH_NAME}:"
    for f in $(find -type f); do
        f=$(echo $f | cut -c3-) # remove ./ prefix
        if [ "$f" = "Release" ]; then
            continue
        fi
        echo " $(${HASH_CMD} ${f}  | cut -d" " -f1) $(wc -c $f)"
    done
}

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
    REPO_DIR=${WORKDIR}/repo
    mkdir -m 0755 ${REPO_DIR}

    echo "::notice title=CreateRepodata::Trying to perform mount on ${REPO_DIR}"
    cat ${WORKDIR}/.sftp_password | sshfs -o password_stdin ${INPUT_SFTP_USER}@${INPUT_SFTP_SERVER}:${INPUT_SFTP_REMOTE_PATH} ${REPO_DIR}
    RC=$?

    if [ $RC -eq 0 ]
    then
      if [ -x /usr/bin/createrepo ]
      then
        echo "::notice title=CreateRepodata::Running createrepo for ${INPUT_SFTP_REMOTE_PATH}"
        createrepo -v ${REPO_DIR}
        RC=$?
      fi

      if [ -x /usr/bin/dpkg-scanpackages ]
      then
        ls -lR ${REPO_DIR}/

        if [ -d ${REPO_DIR}/dists -a -d ${REPO_DIR}/pool ]
        then
          echo "::notice title=CreateRepodata::Running dpkg-scanpackages for ${INPUT_SFTP_REMOTE_PATH}"
          for distro_dir in $( find ${REPO_DIR}/dists/ -maxdepth 1 -mindepth 1 -type d )
          do
            distro_name=$( basename $distro_dir )

            [ -d ${distro_dir}/main/binary-all ] || mkdir -m 0755 -p ${distro_dir}/main/binary-all
            [ -d ${distro_dir}/main/binary-amd64 ] || mkdir -m 0755 -p ${distro_dir}/main/binary-amd64

            cd ${REPO_DIR}/
            dpkg-scanpackages --arch all pool/${distro_name} > ${distro_dir}/main/binary-all/Packages
            RC=$(( $RC + $? ))
            dpkg-scanpackages --arch amd64 pool/${distro_name} > ${distro_dir}/main/binary-amd64/Packages
            RC=$(( $RC + $? ))

            gzip -9 < ${distro_dir}/main/binary-all/Packages > ${distro_dir}/main/binary-all/Packages.gz
            RC=$(( $RC + $? ))
            gzip -9 < ${distro_dir}/main/binary-amd64/Packages > ${distro_dir}/main/binary-amd64/Packages.gz
            RC=$(( $RC + $? ))

            cd ${distro_dir}
            cat > Release << EOTEXT
Origin: LHQG repository
Label: LHQG
Suite: stable
Codename: ${distro_name}
Version: 1.0
Architectures: all amd64
Components: main
Description: LHQG repository
Date: $(date -Ru)
EOTEXT
            RC=$(( $RC + $? ))
            do_hash "MD5sum" "md5sum" >> Release
            RC=$(( $RC + $? ))
            do_hash "SHA1" "sha1sum" >> Release
            RC=$(( $RC + $? ))
            do_hash "SHA256sum" "sha256sum" >> Release
            RC=$(( $RC + $? ))
          done
        else
          echo "::error title=CreateRepodata::No dists or no pool subdirectory found in ${INPUT_SFTP_REMOTE_PATH}"
          RC=1
        fi
      fi
    else
      echo "::error title=CreateRepodata::Unable to perform SSHFS mount"
    fi

    cd ${WORKDIR}
    fusermount -u ${REPO_DIR} > /dev/null 2>&1
  else
    echo "::error title=CreateRepodata::No SSH key type or fingerprint."
  fi
else
  echo "::error title=CreateRepodata::Unable to find the SFTP password file under ${WORKDIR}"
fi

rm -f $LOCKFILE

exit $RC