FROM janeczku/alpine-haproxy:1.6
COPY haproxy.cfg.example /etc/haproxy/haproxy.cfg
COPY acme-http01-webroot.lua /etc/haproxy/
COPY haproxy.pem /etc/letsencrypt/live/www.example.com/
COPY 123456 /var/tmp/.well-known/acme-challenge/

EXPOSE 80 443

CMD [ "/usr/sbin/haproxy", "-f", "/etc/haproxy/haproxy.cfg", "-db" ]