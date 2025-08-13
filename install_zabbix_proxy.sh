#!/bin/bash

# Script para instalacao do Zabbix Proxy 6.0 no Ubuntu 20.04 via compilacao
# Baseado no documento fornecido

# Prompt para variaveis personalizaveis
echo "Digite o Nome do Proxy no Frontend (Hostname para zabbix_proxy.conf):"
read PROXY_HOSTNAME
echo "Digite o Servidor Zabbix (Server para zabbix_proxy.conf, default: zabbix.xlogic.com.br):"
read ZABBIX_SERVER
if [ -z "$ZABBIX_SERVER" ]; then
    ZABBIX_SERVER="zabbix.xlogic.com.br"
fi
echo "Digite o Nome do Host no Frontend (Hostname para zabbix_agentd.conf):"
read AGENT_HOSTNAME
echo "Digite o IP do Proxy (para Server e ServerActive em zabbix_agentd.conf):"
read PROXY_IP

# Senhas hardcoded conforme documento (nao recomendado para producao)
MYSQL_ROOT_PASS="mysql.xlogic"
ZABBIX_DB_PASS="@@Zabbix.xlogic20"

# Instalando repositorio dependencias
apt update && apt upgrade -y
apt install -y libmysqlclient-dev libxml2-dev libsnmp-dev libssh2-1-dev libopenipmi-dev libevent-dev openjdk-8-jdk curl libcurl4-openssl-dev fping libpcre3-dev gnutls-bin libgnutls28-dev make gcc unixodbc unixodbc-dev mysql-server

# Criando Usuario e atribuindo permissoes necessarias
addgroup --system --quiet zabbix
adduser --quiet --system --disabled-login --ingroup zabbix --home /var/lib/zabbix --no-create-home zabbix
mkdir -m u=rwx,g=rwx,o= -p /var/lib/zabbix
chown zabbix:zabbix /var/lib/zabbix

# Copiando o utilitario fping para a pasta padrao e aplicando permissao
cp /usr/bin/fping /usr/local/sbin/
cp /usr/bin/fping /usr/local/bin/
cp /usr/bin/fping /usr/sbin/
cp /usr/bin/fping6 /usr/local/sbin/
cp /usr/bin/fping6 /usr/local/bin/
cp /usr/bin/fping6 /usr/sbin/
chmod 6755 /usr/sbin/fping
chown root:zabbix /usr/sbin/fping
chmod +s /usr/sbin/fping

# Baixando Arquivos para compilacao e Instalando
cd /opt/
wget https://cdn.zabbix.com/zabbix/sources/stable/6.0/zabbix-6.0.9.tar.gz
tar xzvf zabbix-6.0.9.tar.gz
cd zabbix-6.0.9
./configure --enable-proxy --with-net-snmp --with-mysql --with-ssh2 --with-libcurl --enable-agent --enable-java --with-openipmi --with-gnutls --with-unixodbc
make install

# Criando Nova Database
mysql -uroot -p"$MYSQL_ROOT_PASS" <<EOF
create database zabbix character set utf8 collate utf8_bin;
create user 'zabbix'@'%' identified by '$ZABBIX_DB_PASS';
grant all privileges on *.* to 'zabbix'@'%';
flush privileges;
EOF

cd /opt/zabbix-6.0.9/database/mysql
mysql -uzabbix -p"$ZABBIX_DB_PASS" zabbix < schema.sql

# Ajustando Arquivos de Configuracao
mv /usr/local/etc/zabbix_proxy.conf /usr/local/etc/zabbix_proxy.conf_ORIGINAL
mv /usr/local/etc/zabbix_agentd.conf /usr/local/etc/zabbix_agentd.conf_ORIGINAL
cd /usr/local/etc/
wget https://xlogic-cmcl.s3.amazonaws.com/suporte/zabbix/zabbix_proxy.conf
wget https://xlogic-cmcl.s3.amazonaws.com/suporte/zabbix/zabbix_agentd.conf

# Ajustar parametros em zabbix_proxy.conf
sed -i "s/^Hostname=.*/Hostname=$PROXY_HOSTNAME/" /usr/local/etc/zabbix_proxy.conf
sed -i "s/^Server=.*/Server=$ZABBIX_SERVER/" /usr/local/etc/zabbix_proxy.conf

# Ajustar parametros em zabbix_agentd.conf
sed -i "s/^Hostname=.*/Hostname=$AGENT_HOSTNAME/" /usr/local/etc/zabbix_agentd.conf
sed -i "s/^Server=.*/Server=$PROXY_IP/" /usr/local/etc/zabbix_agentd.conf
sed -i "s/^ServerActive=.*/ServerActive=$PROXY_IP/" /usr/local/etc/zabbix_agentd.conf
sed -i "s/#UserParameter=BACULA.discovery,/UserParameter=BACULA.discovery,/g" /usr/local/etc/zabbix_agentd.conf
sed -i "s/#UserParameter=BACULA.check$1$,/UserParameter=BACULA.check[1],/g" /usr/local/etc/zabbix_agentd.conf

# Configurando Servicos do Proxy e Agent
cd /etc/init.d/
wget https://xlogic-cmcl.s3.amazonaws.com/suporte/zabbix/zabbix-agent
wget https://xlogic-cmcl.s3.amazonaws.com/suporte/zabbix/zabbix-proxy
chmod +x /etc/init.d/zabbix-*
update-rc.d zabbix-agent defaults
update-rc.d zabbix-proxy defaults

# Iniciando Servicos do Proxy e Agent
systemctl start zabbix-proxy
systemctl start zabbix-agent