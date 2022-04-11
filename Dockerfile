FROM library/tomcat:9-jre11

ENV ARCH=amd64 \
    GUAC_VER=1.4.0 \
    GUACAMOLE_HOME=/app/guacamole \
    PG_MAJOR=9.6 \
    PGDATA=/config/postgres \
    POSTGRES_USER=guacamole \
    POSTGRES_DB=guacamole_db

# Add Postgres Repository
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" >> /etc/apt/sources.list.d/pgdg.list && \
    wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | apt-key add -

# Install dependencies
RUN apt-get update \
 && apt-get install -y \
    libcairo2-dev libjpeg62-turbo-dev libpng-dev \
    libossp-uuid-dev libavcodec-dev libavutil-dev \
    libswscale-dev freerdp2-dev libfreerdp-client2-2 libpango1.0-dev \
    libssh2-1-dev libtelnet-dev libvncserver-dev \
    libpulse-dev libssl-dev libvorbis-dev libwebp-dev libwebsockets-dev \
    ghostscript build-essential postgresql-${PG_MAJOR} \
  && rm -rf /var/lib/apt/lists/*


# Apply the s6-overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v2.2.0.3/s6-overlay-${ARCH}.tar.gz /tmp
RUN tar -xzf /tmp/s6-overlay-${ARCH}.tar.gz -C / \
 && tar -xzf /tmp/s6-overlay-${ARCH}.tar.gz -C /usr ./bin \
 && rm -rf /tmp/s6-overlay-${ARCH}.tar.gz

RUN mkdir -p ${GUACAMOLE_HOME} \
    ${GUACAMOLE_HOME}/lib \
    ${GUACAMOLE_HOME}/extensions

WORKDIR ${GUACAMOLE_HOME}

# Link FreeRDP to where guac expects it to be
RUN [ "$ARCH" = "armhf" ] && ln -s /usr/local/lib/freerdp /usr/lib/arm-linux-gnueabihf/freerdp || exit 0
RUN [ "$ARCH" = "amd64" ] && ln -s /usr/local/lib/freerdp /usr/lib/x86_64-linux-gnu/freerdp || exit 0

RUN echo $PATH

# Install guacamole-server
RUN curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/source/guacamole-server-${GUAC_VER}.tar.gz" \
 && tar -xzf guacamole-server-${GUAC_VER}.tar.gz \
 && cd guacamole-server-${GUAC_VER} \
 && ./configure --enable-allow-freerdp-snapshots \
 && make -j$(getconf _NPROCESSORS_ONLN) \
 && make install \
 && cd .. \
 && rm -rf guacamole-server-${GUAC_VER}.tar.gz guacamole-server-${GUAC_VER} \
 && ldconfig

# Install guacamole-client and postgres auth adapter
COPY guacamole-${GUAC_VER}.war ${CATALINA_HOME}/webapps/ROOT.war
RUN set -x \
  && rm -rf ${CATALINA_HOME}/webapps/ROOT \
  # && curl -SLo ${CATALINA_HOME}/webapps/ROOT.war "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-${GUAC_VER}.war" \
  && curl -SLo ${GUACAMOLE_HOME}/lib/postgresql-42.1.4.jar "https://jdbc.postgresql.org/download/postgresql-42.2.24.jar" \
  && curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-auth-jdbc-${GUAC_VER}.tar.gz" \
  && tar -xzf guacamole-auth-jdbc-${GUAC_VER}.tar.gz \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/guacamole-auth-jdbc-postgresql-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions/ \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/schema ${GUACAMOLE_HOME}/ \
  && rm -rf guacamole-auth-jdbc-${GUAC_VER} guacamole-auth-jdbc-${GUAC_VER}.tar.gz

# Add optional extensions
RUN set -xe \
  && mkdir ${GUACAMOLE_HOME}/extensions-available \
  && for i in auth-ldap auth-duo auth-header auth-cas auth-openid auth-quickconnect auth-totp; do \
    echo "https://dlcdn.apache.org/guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz" \
    && curl -SLO "https://dlcdn.apache.org/guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz" \
    && tar -xzf guacamole-${i}-${GUAC_VER}.tar.gz \
    && cp guacamole-${i}-${GUAC_VER}/guacamole-${i}-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions-available/ \
    && rm -rf guacamole-${i}-${GUAC_VER} guacamole-${i}-${GUAC_VER}.tar.gz \
  ;done

ENV PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:$PATH
ENV GUACAMOLE_HOME=/config/guacamole

WORKDIR /config

COPY root /

EXPOSE 8080

ENTRYPOINT [ "/init" ]
