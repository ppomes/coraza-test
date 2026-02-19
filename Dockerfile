# Stage 1: Build libcoraza
FROM golang:1.24 AS libcoraza-build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git autoconf automake libtool gcc make pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch feat/implement-missing-apis --depth 1 \
    https://github.com/ppomes/libcoraza.git /src/libcoraza

WORKDIR /src/libcoraza
RUN ./build.sh && ./configure && make


# Stage 2: Build nginx dynamic module
FROM ubuntu:24.04 AS nginx-build

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx gcc make libpcre2-dev zlib1g-dev libssl-dev \
    dpkg-dev git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Download nginx source matching the installed version
RUN NGINX_VERSION=$(nginx -v 2>&1 | sed 's/.*nginx\///;s/ .*//' ) && \
    echo "Building module for nginx ${NGINX_VERSION}" && \
    curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
      -o /tmp/nginx.tar.gz && \
    tar -xzf /tmp/nginx.tar.gz -C /tmp && \
    mv /tmp/nginx-${NGINX_VERSION} /tmp/nginx-src

# Clone coraza-nginx module
RUN git clone --branch chore/update-latest-libcoraza --depth 1 \
    https://github.com/ppomes/coraza-nginx.git /tmp/coraza-nginx

# Copy libcoraza artifacts from stage 1
COPY --from=libcoraza-build /src/libcoraza/libcoraza.a /usr/local/lib/
COPY --from=libcoraza-build /src/libcoraza/libcoraza.so /usr/local/lib/
COPY --from=libcoraza-build /src/libcoraza/coraza/coraza.h /usr/local/include/coraza/coraza.h

RUN ldconfig

# Build the dynamic module with same flags as the distro nginx
WORKDIR /tmp/nginx-src
RUN ./configure --with-compat --add-dynamic-module=/tmp/coraza-nginx && \
    make modules


# Stage 3: Runtime
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy libcoraza shared library
COPY --from=libcoraza-build /src/libcoraza/libcoraza.so /usr/local/lib/
RUN ldconfig

# Copy nginx module
COPY --from=nginx-build /tmp/nginx-src/objs/ngx_http_coraza_module.so \
    /usr/lib/nginx/modules/

# Download and extract OWASP CRS v4
RUN mkdir -p /etc/coraza/crs && \
    CRS_VERSION="4.23.0" && \
    curl -fSL "https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz" \
      -o /tmp/crs.tar.gz && \
    tar -xzf /tmp/crs.tar.gz -C /tmp && \
    cp /tmp/coreruleset-${CRS_VERSION}/crs-setup.conf.example /etc/coraza/crs/ && \
    cp -r /tmp/coreruleset-${CRS_VERSION}/rules /etc/coraza/crs/ && \
    rm -rf /tmp/crs.tar.gz /tmp/coreruleset-*

# Create log directory for coraza and web root with index
RUN mkdir -p /var/log/coraza /var/www/html && \
    echo "OK" > /var/www/html/index.html

# Copy configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY coraza.conf /etc/coraza/coraza.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
