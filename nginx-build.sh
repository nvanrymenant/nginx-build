#!/usr/bin/env bash

# Exit when one of the commands fail
set -e

# Configure the source directory for our build
SRCDIR="/usr/local/src/nginx"

# Configure logfile
LOGFILE="${PWD}/nginx-build.log"

echo $(date '+%Y-%m-%d %H:%M:%S') "Starting nginx-build..." >> $LOGFILE

# Configure versions to fetch
NGINX=1.15.4
NGX_PAGESPEED=1.13.35.2
OPENSSL=1.1.1
PCRE=pcre-8.42
ZLIB=zlib-1.2.11

# Compiler and linker configuration
CFLAGS="-O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC"
LDFLAGS="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie"

# Check if the source directory exists and make it clean
if [ -d "$SRCDIR" ]; then
    cd $SRCDIR
    rm -rf *
else 
    mkdir $SRCDIR
    cd $SRCDIR
fi

# Backup the existing NGINX configuration
if [ -d "/etc/nginx" ]; then
  mv /etc/nginx "/etc/nginx-backup"
fi

# Update and install prerequisites (Debian 9)
apt-get update && apt-get install -y autoconf automake build-essential git libcurl4-openssl-dev libgeoip-dev liblmdb-dev libpcre3 libpcre3-dev libpcre++-dev libtool libxml2-dev libyajl-dev pkgconf unzip uuid-dev wget zlib1g-dev

# fetch OpenSSL sources
cd $SRCDIR
wget -nv -a $LOGFILE https://www.openssl.org/source/openssl-${OPENSSL}.tar.gz
tar -xvzf openssl-${OPENSSL}.tar.gz
rm -f openssl-${OPENSSL}.tar.gz
cd openssl-${OPENSSL}
./config

# fetch PCRE sources
cd $SRCDIR
wget -nv -a $LOGFILE https://ftp.pcre.org/pub/pcre/${PCRE}.tar.gz
tar -xvzf ${PCRE}.tar.gz
rm -f ${PCRE}.tar.gz

# fetch zlib sources
cd $SRCDIR
wget -nv -a $LOGFILE https://zlib.net/${ZLIB}.tar.gz
tar -xvzf ${ZLIB}.tar.gz
rm -f ${ZLIB}.tar.gz

# fetch ModSecurity sources, compile and install
cd $SRCDIR
git clone --depth 1 -b v3/master https://github.com/SpiderLabs/ModSecurity
cd ModSecurity
git submodule init
git submodule update
./build.sh
./configure
make
make install

# Create subdirectory modules/ under our source dir
mkdir $SRCDIR/modules

# ngx_pagespeed
cd $SRCDIR/modules
wget -nv -a $LOGFILE https://github.com/pagespeed/ngx_pagespeed/archive/v${NGX_PAGESPEED}-stable.zip && unzip v${NGX_PAGESPEED}-stable.zip
rm -f v${NGX_PAGESPEED}-stable.zip
cd incubator-pagespeed-ngx-${NGX_PAGESPEED}-stable
psol_url=https://dl.google.com/dl/page-speed/psol/${NGX_PAGESPEED}.tar.gz
[ -e scripts/format_binary_url.sh ] && psol_url=$(scripts/format_binary_url.sh PSOL_BINARY_URL)
wget -nv -a $LOGFILE ${psol_url}
tar -xzvf $(basename ${psol_url})
rm -f $(basename ${psol_url})

# ngx_brotli
cd $SRCDIR/modules
git clone https://github.com/google/ngx_brotli.git
cd ngx_brotli
git submodule update --init --recursive

# ModSecurity-NGINX connector
cd $SRCDIR/modules
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

# NGINX
cd $SRCDIR
wget -nv -a $LOGFILE https://nginx.org/download/nginx-${NGINX}.tar.gz
tar -xvzf nginx-${NGINX}.tar.gz
rm -f nginx-${NGINX}.tar.gz
cd nginx-${NGINX}

NGINX_OPTIONS="
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--http-client-body-temp-path=/var/cache/nginx/client_temp \
	--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
	--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
	--user=nginx \
	--group=nginx \
	--with-cc-opt=${CFLAGS} \
	--with-ld-opt=${LDFLAGS}"

NGINX_MODULES="--without-http_ssi_module \
	--without-http_scgi_module \
	--without-http_uwsgi_module \
	--without-http_geo_module \
	--without-http_split_clients_module \
	--without-http_memcached_module \
	--without-http_empty_gif_module \
	--without-http_browser_module \
	--with-threads \
	--with-file-aio \
	--with-http_ssl_module \
	--with-http_v2_module \
	--with-http_mp4_module \
	--with-http_auth_request_module \
	--with-http_slice_module \
	--with-http_stub_status_module \
	--with-http_realip_module \
	--with-http_dav_module \
	--with-http_secure_link_module \
	--with-http_sub_module \
	--add-dynamic-module=${SRCDIR}/modules/incubator-pagespeed-ngx-${NGX_PAGESPEED}-stable \
	--add-dynamic-module=${SRCDIR}/modules/ModSecurity-nginx \
	--add-module=${SRCDIR}/modules/ngx_brotli \
	--with-openssl=${SRCDIR}/openssl-${OPENSSL} \
	--with-pcre=${SRCDIR}/${PCRE} \
	--with-pcre-jit \
	--with-zlib=${SRCDIR}/${ZLIB}"

./configure $NGINX_OPTIONS $NGINX_MODULES
make
make install
make clean
strip -s /usr/sbin/nginx*

if [ -d "/etc/nginx-backup" ]; then
  # Restore backup of NGINX configuration files
  mv /etc/nginx-backup /etc/nginx
fi

# Create NGINX cache directories if they do not already exist
if [ ! -d "/var/cache/nginx/" ]; then
  mkdir -p \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp
fi

# Add NGINX group and user if they do not already exist
id -g nginx &>/dev/null || addgroup --system nginx
id -u nginx &>/dev/null || adduser --disabled-password --system --home /var/cache/nginx --shell /sbin/nologin --group nginx

# Hold package "nginx"
apt-mark hold nginx

# Create systemd unit file
cat > /etc/systemd/system/nginx.service <<EOL
[Unit]
Description=A high performance web server and a reverse proxy server
After=network.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOL

# Start and enable NGINX
sudo systemctl start nginx.service && sudo systemctl enable nginx.service

# Remove build-essentials
apt-get remove -y build-essential

echo $(date '+%Y-%m-%d %H:%M:%S') "Finished nginx-build..." >> $LOGFILE