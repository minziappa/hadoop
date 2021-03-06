#!/usr/bin/env bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

function hadoop_usage()
{
  echo "Usage: httpfs.sh [--config confdir] [--debug] --daemon start|status|stop"
  echo "       httpfs.sh [--config confdir] [--debug] COMMAND"
  echo "            where COMMAND is one of:"
  echo "  run               Start httpfs in the current window"
  echo "  run -security     Start in the current window with security manager"
  echo "  start             Start httpfs in a separate window"
  echo "  start -security   Start in a separate window with security manager"
  echo "  status            Return the LSB compliant status"
  echo "  stop              Stop httpfs, waiting up to 5 seconds for the process to end"
  echo "  stop n            Stop httpfs, waiting up to n seconds for the process to end"
  echo "  stop -force       Stop httpfs, wait up to 5 seconds and then use kill -KILL if still running"
  echo "  stop n -force     Stop httpfs, wait up to n seconds and then use kill -KILL if still running"
}

# let's locate libexec...
if [[ -n "${HADOOP_PREFIX}" ]]; then
  DEFAULT_LIBEXEC_DIR="${HADOOP_PREFIX}/libexec"
else
  this="${BASH_SOURCE-$0}"
  bin=$(cd -P -- "$(dirname -- "${this}")" >/dev/null && pwd -P)
  DEFAULT_LIBEXEC_DIR="${bin}/../libexec"
fi

HADOOP_LIBEXEC_DIR="${HADOOP_LIBEXEC_DIR:-$DEFAULT_LIBEXEC_DIR}"
# shellcheck disable=SC2034
HADOOP_NEW_CONFIG=true
if [[ -f "${HADOOP_LIBEXEC_DIR}/httpfs-config.sh" ]]; then
  . "${HADOOP_LIBEXEC_DIR}/httpfs-config.sh"
else
  echo "ERROR: Cannot execute ${HADOOP_LIBEXEC_DIR}/httpfs-config.sh." 2>&1
  exit 1
fi

# The Java System property 'httpfs.http.port' it is not used by Kms,
# it is used in Tomcat's server.xml configuration file
#

# Mask the trustStorePassword
# shellcheck disable=SC2086
CATALINA_OPTS_DISP="$(echo ${CATALINA_OPTS} | sed -e 's/trustStorePassword=[^ ]*/trustStorePassword=***/')"

hadoop_debug "Using   CATALINA_OPTS:       ${CATALINA_OPTS_DISP}"

# We're using hadoop-common, so set up some stuff it might need:
hadoop_finalize

hadoop_verify_logdir

if [[ $# = 0 ]]; then
  case "${HADOOP_DAEMON_MODE}" in
    status)
      hadoop_status_daemon "${CATALINA_PID}"
      exit
    ;;
    start)
      set -- "start"
    ;;
    stop)
      set -- "stop"
    ;;
  esac
fi

hadoop_finalize_catalina_opts
export CATALINA_OPTS

# A bug in catalina.sh script does not use CATALINA_OPTS for stopping the server
#
if [[ "${1}" = "stop" ]]; then
  export JAVA_OPTS=${CATALINA_OPTS}
fi

# If ssl, the populate the passwords into ssl-server.xml before starting tomcat
#
# HTTPFS_SSL_KEYSTORE_PASS is a bit odd.
# if undefined, then the if test will not enable ssl on its own
# if "", set it to "password".
# if custom, use provided password
#
if [[ -f "${HADOOP_CATALINA_HOME}/conf/ssl-server.xml.conf" ]]; then
  if [[ -n "${HTTPFS_SSL_KEYSTORE_PASS+x}" ]] || [[ -n "${HTTPFS_SSL_TRUSTSTORE_PASS}" ]]; then
    export HTTPFS_SSL_KEYSTORE_PASS=${HTTPFS_SSL_KEYSTORE_PASS:-password}
    sed -e 's/_httpfs_ssl_keystore_pass_/'${HTTPFS_SSL_KEYSTORE_PASS}'/g' \
        -e 's/_httpfs_ssl_truststore_pass_/'${HTTPFS_SSL_TRUSTSTORE_PASS}'/g' \
      "${HADOOP_CATALINA_HOME}/conf/ssl-server.xml.conf" \
      > "${HADOOP_CATALINA_HOME}/conf/ssl-server.xml"
    chmod 700 "${HADOOP_CATALINA_HOME}/conf/ssl-server.xml" >/dev/null 2>&1
  fi
fi

hadoop_add_param CATALINA_OPTS -Dhttpfs.http.hostname "-Dhttpfs.http.hostname=${HTTPFS_HOST_NAME}"
hadoop_add_param CATALINA_OPTS -Dhttpfs.ssl.enabled "-Dhttpfs.ssl.enabled=${HTTPFS_SSL_ENABLED}"

exec "${HADOOP_CATALINA_HOME}/bin/catalina.sh" "$@"
