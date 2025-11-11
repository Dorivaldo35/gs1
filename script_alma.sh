#!/bin/bash

set -e


IP_FIXO="192.168.56.201"
NETMASK="255.255.255.0"
NIC="enp0s8"
DOMAIN="<seu_dominio>.local"
WEB_DIR="/var/www/html"
SITE_URL=""
ZONE_DIR="/var/named"
ZONE_FILE="$ZONE_DIR/$DOMAIN.zone"
DNS_CONF="/etc/named.conf"


log()  { echo -e "[*] $*"; }
ok()   { echo -e "[OK] $*"; }
erro() { echo -e "[ERROR] $*" >&2; exit 1; }

configurar_ip() {
    log "Configurando IP na interface $NIC..."
    ifconfig "$NIC" "$IP_FIXO" netmask "$NETMASK" up || erro "Falha ao configurar IP"
    ok "IP configurado: $IP_FIXO"
}


instalar_dependencias() {
    log "Instalando Apache + Ferramentas..."
    yum install -y httpd wget unzip bind bind-utils net-tools >/dev/null || erro "Falha no yum install"
    ok "Pacotes baixados e instalados"
}


iniciar_webserver() {
    log "Iniciando Apache..."
    systemctl enable --now httpd >/dev/null
    systemctl is-active --quiet httpd || erro "Apache não iniciou"
    ok "Apache funcionando"
}


configurar_site() {
    log "publicando site..."

    rm -rf "$WEB_DIR"/*
    wget -q "$SITE_URL" -O /tmp/site.zip || erro "Falha ao baixar site"

    rm -rf /tmp/site_extract
    mkdir /tmp/site_extract
    unzip -q /tmp/site.zip -d /tmp/site_extract || erro "Falha ao extrair site"

    SITE_FOLDER=$(find /tmp/site_extract -mindepth 1 -maxdepth 1 -type d | head -n 1)

    mv "$SITE_FOLDER"/* "$WEB_DIR"/ || erro "Falha ao mover arquivos do site"

    chown -R apache:apache "$WEB_DIR"
    ok "Site publicado aqui: http://$IP_FIXO"
}


configurar_dns() {
    log "Configurando DNS com Bind..."

    echo "$DOMAIN" > /etc/hostname

    cat > "$DNS_CONF" <<EOF
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    directory "/var/named";
    allow-query { any; };
    recursion no;
};
zone "$DOMAIN" IN {
    type master;
    file "$DOMAIN.zone";
};
EOF

    cat > "$ZONE_FILE" <<EOF
\$TTL 300
@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
        2024111001
        7200
        3600
        86400
        300
)
@       IN      NS      ns1.$DOMAIN.

@       IN      A       $IP_FIXO
ns1     IN      A       $IP_FIXO
www     IN      A       $IP_FIXO
mail    IN      A       $IP_FIXO

@       IN      MX 10   mail.$DOMAIN.
EOF

    chown named:named "$ZONE_FILE"

    named-checkconf || erro "Erro no named.conf"
    named-checkzone "$DOMAIN" "$ZONE_FILE" || erro "Erro no arquivo de zona"

    systemctl enable --now named >/dev/null || erro "Erro ao iniciar Bind"
    ok "DNS configurado corretamente"
}


main() {
    log "INICIANDO CONFIGURAÇÃO"
    configurar_ip
    instalar_dependencias
    iniciar_webserver
    configurar_site
    configurar_dns
    ok "Configuração feita!"
    echo -e "\nAcesse: http://$IP_FIXO"
    echo "Ou configure /etc/hosts em outra máquina:"
    echo "   $IP_FIXO  $DOMAIN  www.$DOMAIN"
}

main
