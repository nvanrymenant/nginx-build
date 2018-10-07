#!/usr/bin/env bash

# Configure BASH options
set -e # Exit if one of the commands fail

# Global parameters
BUILDDIR="/usr/local/src/nginx" # Set the default location to download sources and built NGINX
EXPORTDIR="/var/cache/apt/archives" # Set the location where to save the generated .deb packages
LOGFILE="${PWD}/nginx-build.log" # Set the default logfile

# Optional packages to build
# Make sure to also uncomment the corresponding line to add the module to NGINX ./configure
MODSECURITY=0
NAXSI=0
NGX_PAGESPEED=0
NGX_BROTLI=0
NGX_FANCYINDEX=0

# Versions of required packages
NGINX_VERSION=1.14.0 #current NGINX stable version
OPENSSL_VERSION=1.1.1 #OpenSSL LTS version
PCRE_VERSION=pcre-8.42
ZLIB_VERSION=zlib-1.2.11
LIBATOMIC_VERSION=7.6.6 #libatomic stable version

# Source URL's for required packages
NGINX_URL="https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
OPENSSL_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
PCRE_URL="https://ftp.pcre.org/pub/pcre/${PCRE_VERSION}.tar.gz"
ZLIB_URL="https://zlib.net/${ZLIB_VERSION}.tar.gz"
LIBATOMIC_URL="https://github.com/ivmai/libatomic_ops/releases/download/v7.6.6/libatomic_ops-${LIBATOMIC_VERSION}.tar.gz"

# Versions for optional packages
LIBMODSECURITY_VERSION=v3/master
NAXSI_VERSION=0.56
NGX_PAGESPEED_VERSION=1.13.35.2

# Source URL's for optional packages
LIBMODSECURITY_URL="https://github.com/SpiderLabs/ModSecurity"
NAXSI_URL="https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz"
MODSECURITY_NGINX_URL="https://github.com/SpiderLabs/ModSecurity-nginx.git"
NGX_PAGESPEED_URL="https://github.com/pagespeed/ngx_pagespeed/archive/v${NGX_PAGESPEED_VERSION}-stable.zip"
NGX_BROTLI_URL="https://github.com/google/ngx_brotli.git"
NGX_FANCYINDEX_URL="https://github.com/aperezdc/ngx-fancyindex.git"

echo $(date '+%Y-%m-%d %H:%M:%S') "Starting nginx-build..." >> $LOGFILE

# Check if the source directory exists and clean if it does
if [ -d "${BUILDDIR}" ]; then
    cd $BUILDDIR
    rm -rf *
	rm -rf modules
	mkdir $BUILDDIR/modules	
else 
    mkdir $BUILDDIR
	mkdir $BUILDDIR/modules	
    cd $BUILDDIR
fi

# Update and install prerequisites (Debian 9.x)
apt-get update && apt-get install -y autoconf automake build-essential checkinstall git libcurl4-openssl-dev libgeoip-dev liblmdb-dev libpcre3 libpcre3-dev libpcre++-dev libtool libxml2-dev libyajl-dev pkgconf unzip uuid-dev wget zlib1g-dev

# Get and configure OpenSSL sources
cd $BUILDDIR
wget -nv -a $LOGFILE $OPENSSL_URL
tar -xvzf openssl-${OPENSSL_VERSION}.tar.gz
rm -f openssl-${OPENSSL_VERSION}.tar.gz
cd openssl-${OPENSSL_VERSION}
./config

# get PCRE sources
cd $BUILDDIR
wget -nv -a $LOGFILE $PCRE_URL
tar -xvzf ${PCRE_VERSION}.tar.gz
rm -f ${PCRE_VERSION}.tar.gz

# get zlib sources
cd $BUILDDIR
wget -nv -a $LOGFILE $ZLIB_URL
tar -xvzf $BUILDDIR/${ZLIB_VERSION}.tar.gz
rm -f $BUILDDIR/${ZLIB_VERSION}.tar.gz

# get libatomic sources
cd $BUILDDIR
wget -nv -a $LOGFILE $LIBATOMIC_URL
tar -xvzf $BUILDDIR/libatomic_ops-${LIBATOMIC_VERSION}.tar.gz
rm -f $BUILDDIR/libatomic_ops-${LIBATOMIC_VERSION}.tar.gz
cd libatomic_ops-${LIBATOMIC_VERSION}
./configure
make
cp /usr/local/src/nginx/libatomic_ops-${LIBATOMIC_VERSION}/src/.libs/libatomic_ops.a /usr/local/src/nginx/libatomic_ops-${LIBATOMIC_VERSION}/src/libatomic_ops.a 

# Get and configure sources for the optional modules

if [ $MODSECURITY = 1 ] ; then
	# get libModSecurity sources, compile and install
	cd $BUILDDIR
	git clone --depth 1 -b $LIBMODSECURITY $LIBMODSECURITY_URL
	cd ModSecurity
	git submodule init
	git submodule update
	./build.sh
	./configure
	make
	# Create libModSecurity .deb package
	checkinstall --pakdir $EXPORTDIR --strip --install=no -y 
	# get ModSecurity-NGINX connector
	cd $BUILDDIR/modules
	git clone --depth 1 $MODSECURITY_NGINX_URL
fi

if [ $NAXSI = 1 ]; then
	cd $BUILDDIR
	wget -nv -a $LOGFILE $NAXSI_URL
	tar -xvzf ${NAXSI_VERSION}.tar.gz
	rm -f ${NAXSI_VERSION}.tar.gz
fi

if [ $NGX_PAGESPEED = 1 ]; then
	cd $BUILDDIR/modules
	wget -nv -a $LOGFILE $NGX_PAGESPEED_URL
	unzip v${NGX_PAGESPEED_VERSION}-stable.zip
	rm -f v${NGX_PAGESPEED_VERSION}-stable.zip
	cd incubator-pagespeed-ngx-${NGX_PAGESPEED_VERSION}-stable
	psol_url=https://dl.google.com/dl/page-speed/psol/${NGX_PAGESPEED_VERSION}.tar.gz
	[ -e scripts/format_binary_url.sh ] && psol_url=$(scripts/format_binary_url.sh PSOL_BINARY_URL)
	wget -nv -a $LOGFILE ${psol_url}
	tar -xzvf $(basename ${psol_url})
	rm -f $(basename ${psol_url})
fi

if [ $NGX_BROTLI = 1 ]; then
	cd $BUILDDIR/modules
	git clone $NGX_BROTLI_URL
	cd ngx_brotli
	git submodule update --init --recursive

fi

if [ $NGX_FANCYINDEX = 1 ]; then
	cd $BUILDDIR/modules
	git clone $NGX_FANCYINDEX_URL
	cd ngx-fancyindex
fi

# Get NGINX sources and start the build
cd $BUILDDIR
wget -nv -a $LOGFILE $NGINX_URL
tar -xvzf nginx-${NGINX_VERSION}.tar.gz
rm -f nginx-${NGINX_VERSION}.tar.gz
cd nginx-${NGINX_VERSION}
./configure \
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
--with-cc-opt="-O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC" \
--with-ld-opt="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie" \
--without-http_ssi_module \
--without-http_scgi_module \
--without-http_uwsgi_module \
--without-http_grpc_module \
--without-http_geo_module \
--without-http_split_clients_module \
--without-http_memcached_module \
--without-http_empty_gif_module \
--without-http_browser_module \
--without-http_autoindex_module \
--with-threads \
--with-file-aio \
--with-http_ssl_module \
--with-http_v2_module \
--with-openssl=${BUILDDIR}/openssl-${OPENSSL_VERSION} \
--with-openssl-opt="-fstack-protector-strong" \
--with-pcre=${BUILDDIR}/${PCRE_VERSION} \
--with-pcre-jit \
--with-zlib=${BUILDDIR}/${ZLIB_VERSION} \
--with-libatomic=${BUILDDIR}/libatomic_ops-${LIBATOMIC_VERSION}

# Optional modules to add to ./configure
#--with-stream=dynamic
#--with-stream_ssl_module
#--with-stream_ssl_preread_module
#--with-http_mp4_module
#--with-http_auth_request_module
#--with-http_slice_module
#--with-http_stub_status_module
#--with-http_realip_module
#--with-http_secure_link_module
#--with-http_sub_module
#--with-http_stub_status_module
#--with-http_dav_module
#--add-module=${BUILDDIR}/modules/ModSecurity-nginx
#--add-module=${BUILDDIR}/modules/naxsi-{$NAXSI_VERSION}
#--add-dynamic-module=${BUILDDIR}/modules/incubator-pagespeed-ngx-${NGX_PAGESPEED_VERSION}-stable
#--add-dynamic-module=${BUILDDIR}/modules/ngx_brotli
#--add-dynamic-module=${BUILDDIR}/modules/ngx-fancyindex

make

# Create NGINX .deb package
checkinstall --pakdir $EXPORTDIR --strip --install=no -y

echo $(date '+%Y-%m-%d %H:%M:%S') "Finished nginx-build..." >> $LOGFILE