#!/bin/sh
set -x

appSetup () {
  #BEGIN Set variables
  DOMAIN=${DOMAIN:-SAMDOM.LOCAL}
  DOMAINUSER=${DOMAINUSER:-Administrator}
  DOMAINPASS=${DOMAINPASS:-Pa!!word1}

  BIND_INTERFACES_ONLY=${BIND_INTERFACES_ONLY:-true}
  BIND_INTERFACES=${BIND_INTERFACES:-eth0 lo}

  WINBIND_REFRESH_TICKETS=${WINBIND_REFRESH_TICKETS:-false}
  WINBIND_USE_DEFAULT_DOMAIN=${WINBIND_USE_DEFAULT_DOMAIN:-false}

  #Enables Debug - Raise log level as needed
  DEBUG=${DEBUG:-false}
  DEBUGLEVEL=${DEBUGLEVEL:-1}
  LOG_LEVEL=${LOG_LEVEL:-0}

  # List of DCs to get time from
  NTPSERVERLIST=${NTPSERVERLIST:-DC01}
  
  #Change if hostname includes DNS/DOMAIN SUFFIX e.g. host.example.com - it should only display host
  NETBIOS_NAME=${NETBIOS_NAME:-$(hostname)}

  #If true idmap AD-BACKEND, if false idmap RID-BACKEND
  RFC2307=${RFC2307:-true}

  #IDMAP IDMIN-IDMAX
  IDMIN=${IDMIN:-10000}
  IDMAX=${IDMAX:-999999}

  #END Set variables

  LDOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')
  UDOMAIN=$(echo "$LDOMAIN" | tr '[:lower:]' '[:upper:]')
  URDOMAIN=$(echo "$UDOMAIN" | cut -d "." -f1)
  if [ ! -d /etc/samba/external/ ]; then
    mkdir /etc/samba/external/
  fi

  if [ ! -f /etc/samba/lmhosts ]; then
  touch /etc/samba/lmhosts
  fi

  if [ "$DEBUG" = "true" ]; then
    SAMBA_DEBUG_OPTION="-d $DEBUGLEVEL"
    NTP_DEBUG_OPTION="-D $DEBUGLEVEL"
  else
    SAMBA_DEBUG_OPTION=""
    NTP_DEBUG_OPTION=""
  fi

  if [ ! -f /etc/samba/external/smb.conf ]; then
    sed -i "s:MYDOMAIN:$(echo "$URDOMAIN" | tr '[:upper:]' '[:lower:]'):" /etc/freeradius/3.0/mods-available/ntlm_auth
    sed -e "s:{{ NETBIOS_NAME }}:$NETBIOS_NAME:" \
      -e "s:{{ UDOMAIN }}:$UDOMAIN:" \
      -e "s:{{ URDOMAIN }}:$URDOMAIN:" \
      -e "s:{{ LOG_LEVEL }}:$LOG_LEVEL:" \
      -e "s:{{ WINBIND_REFRESH_TICKETS }}:$WINBIND_REFRESH_TICKETS:" \
      -e "s:{{ WINBIND_USE_DEFAULT_DOMAIN }}:$WINBIND_USE_DEFAULT_DOMAIN:" \
      -e "s:{{ IDMIN }}:$IDMIN:" \
      -e "s:{{ IDMAX }}:$IDMAX:" \
    -i /etc/samba/smb.conf
  
  #Remove unused backend
  if [ "$RFC2307" != true ]; then
    sed -i '/#AD-BACKEND BEGIN,/#AD-BACKEND END/d' /etc/samba/smb.conf
  else
    sed -i '/#RID-BACKEND BEGIN/,/#RID-BACKEND END/d' /etc/samba/smb.conf
  fi

  if [ ! -f /etc/samba/user.map ]; then
    touch /etc/samba/user.map
  fi

  if [ "$BIND_INTERFACES_ONLY" = true ]; then
    sed -i "s:{{ INTERFACES }}:$BIND_INTERFACES:" /etc/samba/smb.conf
    sed -i "s:{{ BIND_INTERFACES_ONLY }}:$BIND_INTERFACES_ONLY:" /etc/samba/smb.conf
  fi
  
  sed -e "s:{{ UDOMAIN }}:$UDOMAIN:" \
    -e "s:{{ LDOMAIN }}:$LDOMAIN:" \
  -i /etc/krb5.conf
  
  sed -e "s:{{ SAMBA_DEBUG_OPTION }}:$SAMBA_DEBUG_OPTION:" \
    -e "s:{{ NTP_DEBUG_OPTION }}:$NTP_DEBUG_OPTION:" \
  -i /etc/supervisor/conf.d/supervisord.conf

  #unlimited NTP Server; delimiter is " " aka space
  DCs=$(echo "$NTPSERVERLIST" | tr " " "\n")
  NTPSERVER=""
  NTPSERVERRESTRICT=""
  for DC in $DCs
  do
    NTPSERVER="$NTPSERVER server ${DC}.${LDOMAIN}    iburst\n"
    NTPSERVERRESTRICT="$NTPSERVERRESTRICT restrict ${DC}.${LDOMAIN}  mask 255.255.255.255    nomodify notrap nopeer noquery\n"
  done

  sed -e "s:{{ NTPSERVER }}:$NTPSERVER:" \
    -e "s:{{ NTPSERVERRESTRICT }}:$NTPSERVERRESTRICT:" \
  -i /etc/ntp.conf

  cp -f /etc/samba/smb.conf /etc/samba/external/smb.conf
    appFirstStart
  else
    cp -f /etc/samba/external/smb.conf /etc/samba/smb.conf
    appStart
  fi
}

appFirstStart () {
    net ads join -U "$DOMAINUSER"%"$DOMAINPASS" "$UDOMAIN" "$SAMBA_DEBUG_OPTION"
    /usr/bin/supervisord -c "/etc/supervisor/supervisord.conf"
}

appStart () {
    /usr/bin/supervisord -c "/etc/supervisor/supervisord.conf"
}

case "$1" in
    start)
        if [ -f /etc/samba/external/smb.conf ]; then
            cp /etc/samba/external/smb.conf /etc/samba/smb.conf
            appStart
        else
            echo "Config file is missing."
        fi
        ;;
    setup)
        # If the supervisor conf isn't there, we're spinning up a new container
        if [ -f /etc/samba/external/smb.conf ]; then
            appStart
        else
            appSetup
        fi
        ;;
esac

exit 0