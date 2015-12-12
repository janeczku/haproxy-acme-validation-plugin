#/bin/bash
# automation of certificate renewal for let's encrypt and haproxy
# - checks all certificates under /etc/letsencrypt/live and renews
#   those about about to expire in less than 4 weeks
# - creates haproxy.pem files in /etc/letsencrypt/live/domain.tld/
# - soft-restarts haproxy to apply new certificates
# usage:
# ./cert-renew-haproxy.sh

###################
## configuration ##
###################

EMAIL="your_le_account@email.com"

LE_CLIENT="/path/to/letsencrypt-auto"

HAPROXY_RELOAD_CMD="service haproxy reload"

WEBROOT="/var/tmp"

LOG_TO_FILE="/var/log/certrenew.log"

######################
## utility function ##
######################

function issueCert {
  $LE_CLIENT certonly --text --webroot --webroot-path ${WEBROOT} --renew-by-default --agree-tos --email ${EMAIL} $1 > /dev/null
  return $?
}

function logger_warn {
  if [ -n "${LOG_TO_FILE}" ]
  then
    echo "[error] ${1}\n" >> ${LOG_TO_FILE}
  fi
  >&2 echo "[error] ${1}"
}

function logger_info {
  if [ -n "${LOG_TO_FILE}" ]
  then
    echo "[info] ${1}\n" >> ${LOG_TO_FILE}
  else
    echo "[info] ${1}"
  fi
}

##################
## main routine ##
##################

le_cert_root="/etc/letsencrypt/live"

if [ ! -d ${le_cert_root} ]; then
  logger_warn "${le_cert_root} does not exist!"
  exit 1
fi

# check certificate expiration and run certificate issue requests
# for those that expire in under 4 weeks
renewed_certs=()
exitcode=0
while IFS= read -r -d '' cert; do
  if ! openssl x509 -noout -checkend $((4*7*86400)) -in "${cert}"; then
    subject="$(openssl x509 -noout -subject -in "${cert}" | grep -o -E 'CN=[^ ,]+' | tr -d 'CN=')"
    subjectaltnames="$(openssl x509 -noout -text -in "${cert}" | sed -n '/X509v3 Subject Alternative Name/{n;p}' | sed 's/\s//g' | tr -d 'DNS:' | sed 's/,/ /g')"
    domains="-d ${subject}"
    for name in ${subjectaltnames}; do
      if [ "${name}" != "${subject}" ]; then
        domains="${domains} -d ${name}"
      fi
    done
    issueCert "${domains}"
    if [ $? -ne 0 ]
    then
      logger_warn "failed to renew certificate! check /var/log/letsencrypt/letsencrypt.log!"
      exitcode=1
    else
      renewed_certs+=("$subject")
      logger_info "renewed certificate for ${subject}"
    fi
  fi
done < <(find /etc/letsencrypt/live -name cert.pem -print0)

# create haproxy.pem file(s)
for domain in ${renewed_certs[@]}; do
  cat ${le_cert_root}/${domain}/privkey.pem ${le_cert_root}/${domain}/fullchain.pem > ${le_cert_root}/${domain}/haproxy.pem
  if [ $? -ne 0 ]; then
    logger_warn "failed to create haproxy.pem file!"
    exit 1
  fi
done

# soft-restart haproxy
$HAPROXY_RELOAD_CMD
if [ $? -ne 0 ]; then
  logger_warn "failed to create haproxy.pem file!"
  exit 1
fi

exit ${exitcode}