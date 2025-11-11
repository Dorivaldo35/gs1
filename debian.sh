#!/bin/bash

set -e

IP_FIXO="192.168.56.201"
NETMASK="255.255.255.0"
NIC="enp0s8"
DOMAIN="dorivaldo.local"  # 👈 ALTERE PARA SEU DOMÍNIO (ex: empresa.local)
WEB_DIR="/var/www/html"
SITE_URL="https://exemplo.com/seu-site.zip"  # 👈 ALTERE PARA SEU ZIP REAL
ZONE_DIR="/etc/bind"
ZONE_FILE="$ZONE_DIR/db.$DOMAIN"
DNS_CONF="/etc/bind/named.conf.local"

log()  { echo -e "[*] $*"; }
ok()   { echo -e "[OK] $*"; }
erro() { echo -e "[ERROR] $*" >&2; exit 1; }

# Verifica se está rodando como root
[ "$EUID" -ne 0 ] && erro "Execute como root (sudo)"

configurar_ip() {
    log "Configurando IP na interface $NIC..."
    ip addr add "$IP_FIXO/$NETMASK" dev "$NIC" 2>/dev/null || true
    ip link set "$NIC" up || erro "Falha ao ativar interface $NIC"
    ok "IP configurado: $IP_FIXO/24 na $NIC"
}

instalar_dependencias() {
    log "Atualizando pacotes e instalando dependências..."
    apt update -y >/dev/null || erro "Falha ao atualizar apt"
    apt install -y apache2 wget unzip bind9 bind9utils net-tools dnsutils >/dev/null || erro "Falha ao instalar pacotes"
    ok "Pacotes instalados: apache2, bind9, etc."
}

iniciar_webserver() {
    log "Iniciando Apache..."
    systemctl enable --now apache2 >/dev/null
    systemctl is-active --quiet apache2 || erro "Apache não iniciou"
    ok "Apache funcionando"
}

configurar_site() {
    log "Publicando site..."

    # Limpar diretório web
    rm -rf "$WEB_DIR"/*

    # Baixar e extrair o site
    wget -q "$SITE_URL" -O /tmp/site.zip || erro "Falha ao baixar site ($SITE_URL)"
    rm -rf /tmp/site_extract && mkdir -p /tmp/site_extract
    unzip -q /tmp/site.zip -d /tmp/site_extract || erro "Falha ao extrair ZIP"

    SITE_FOLDER=$(find /tmp/site_extract -mindepth 1 -maxdepth 1 -type d | head -n1)
    if [ -z "$SITE_FOLDER" ]; then
        # Se não for uma pasta dentro do ZIP, usa o próprio conteúdo
        cp -r /tmp/site_extract/* "$WEB_DIR"/
    else
        mv "$SITE_FOLDER"/* "$WEB_DIR"/ || erro "Falha ao mover arquivos"
    fi

    chown -R www-data:www-data "$WEB_DIR"
    chmod -R 755 "$WEB_DIR"
    ok "Site publicado: http://$IP_FIXO"
}

configurar_dns() {
    log "Configurando DNS com BIND9..."

    # Definir hostname (opcional, mas útil)
    echo "$DOMAIN" > /etc/hostname
    hostname "$DOMAIN" 2>/dev/null || true

    # Configurar zona no named.conf.local
    cat > "$DNS_CONF" <<EOF
zone "$DOMAIN" {
    type master;
    file "/etc/bind/db.$DOMAIN";
};
EOF

    # Criar arquivo de zona
    cat > "$ZONE_FILE" <<EOF
\$TTL 300
@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
        2025111201  ; Serial (YYYYMMDDNN)
        7200        ; Refresh
        3600        ; Retry
        86400       ; Expire
        300 )       ; Negative Cache TTL

@       IN      NS      ns1.$DOMAIN.
@       IN      A       $IP_FIXO
ns1     IN      A       $IP_FIXO
www     IN      A       $IP_FIXO
mail    IN      A       $IP_FIXO
@       IN      MX 10   mail.$DOMAIN.
EOF

    chown root:bind "$ZONE_FILE"
    chmod 644 "$ZONE_FILE"

    # Validar configuração
    named-checkconf || erro "Erro de sintaxe em named.conf"
    named-checkzone "$DOMAIN" "$ZONE_FILE" || erro "Erro no arquivo de zona $ZONE_FILE"

    # Reiniciar BIND
    systemctl enable --now bind9 >/dev/null || erro "Falha ao iniciar bind9"
    systemctl restart bind9 || erro "Falha ao reiniciar bind9"

    ok "DNS configurado: $DOMAIN → $IP_FIXO"
}

testar_dns_localmente() {
    log "Configurando resolução local (opcional)..."
    # Adicionar ao /etc/hosts para teste rápido (apenas local)
    grep -q "$IP_FIXO.*$DOMAIN" /etc/hosts || echo "$IP_FIXO $DOMAIN www.$DOMAIN mail.$DOMAIN ns1.$DOMAIN" >> /etc/hosts
    ok "Entradas adicionadas ao /etc/hosts para teste local"
}

main() {
    log "🚀 INICIANDO CONFIGURAÇÃO AUTOMÁTICA (Debian/Ubuntu)"
    configurar_ip
    instalar_dependencias
    iniciar_webserver
    configurar_site
    configurar_dns
    testar_dns_localmente

    ok "✅ Configuração concluída com sucesso!"
    echo
    echo "➡ Acesse o site em: http://$IP_FIXO ou http://www.$DOMAIN"
    echo
    echo "💡 Para testar o DNS em outras máquinas, configure-as para usarem $IP_FIXO como DNS:"
    echo "   Em /etc/resolv.conf (ou via DHCP):"
    echo "      nameserver $IP_FIXO"
    echo
    echo "🔍 Teste com: dig @$IP_FIXO www.$DOMAIN ou nslookup www.$DOMAIN $IP_FIXO"
}

main
