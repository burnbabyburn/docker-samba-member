FROM ubuntu
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y ntp pkg-config attr acl samba smbclient winbind ldap-utils libnss-winbind libpam-winbind libpam-krb5 krb5-user supervisor dnsutils \
	&& apt-get clean autoclean \
    && apt-get autoremove --yes \
    && rm -rf /var/lib/{apt,dpkg,cache,log}/ && \
    rm -fr /tmp/* /var/tmp/*

COPY entrypoint.sh /entrypoint.sh
COPY /etc /etc/

RUN chmod +x /entrypoint.sh

CMD /entrypoint.sh setup
