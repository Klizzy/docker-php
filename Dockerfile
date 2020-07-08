FROM php:7.3-apache
ENV TIMEZONE Europe/Berlin
ARG APACHE_DOCUMENT_ROOT

MAINTAINER Steven Zemelka <steven.zemelka@gmail.com>

RUN apt-get update && apt-get install -y gnupg vim git curl wget unzip tmux htop sudo libpq-dev zlib1g-dev libicu-dev \
    g++ libgmp-dev libmcrypt-dev libbz2-dev libpng-dev libjpeg62-turbo-dev \
    libfreetype6-dev libfontconfig \
    librabbitmq-dev libssl-dev gcc make autoconf libc-dev pkg-config \
    default-mysql-client libmcrypt-dev libpq-dev libmemcached-dev zsh locales libzip-dev \
     && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
	&& composer --version \
	&& /usr/local/bin/composer global require hirak/prestissimo

# Set timezone
RUN ln -snf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && echo ${TIMEZONE} > /etc/timezone \
	&& printf '[PHP]\ndate.timezone = "%s"\n', ${TIMEZONE} > /usr/local/etc/php/conf.d/tzone.ini \
	&& "date" \
	&& mkdir /usr/local/nvm
ENV NVM_DIR /usr/local/nvm
ENV NVM_VERSION v0.33.11
ENV NODE_VERSION 12.18.2

RUN docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
 && docker-php-ext-install -j$(nproc) gd

# Install oh-my-zsh and set ZSH as default shell
RUN wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true \
	&& chsh -s $(which zsh)

ADD ./.zshrc /root/.zshrc

# NVM & NPM
RUN curl https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | zsh \
 && . $NVM_DIR/nvm.sh \
 && zsh -i -c 'nvm ls-remote' \
 && zsh -i -c 'nvm install $NODE_VERSION'

RUN ln -s $NVM_DIR/versions/node/v$NODE_VERSION/bin/node /usr/local/bin/node \
 && ln -s $NVM_DIR/versions/node/v$NODE_VERSION/bin/npm /usr/local/bin/npm \
 && ln -s $NVM_DIR/versions/node/v$NODE_VERSION/bin/yarn /usr/local/bin/yarn

RUN npm install -g yarn

# Type docker-php-ext-install to see available extensions
RUN docker-php-ext-install -j$(nproc) iconv pdo pgsql pdo_pgsql mysqli pdo_mysql intl bcmath gmp bz2 zip \
    && apt-get clean

# install xdebug and redis
RUN pecl install xdebug \
	&& pecl install -o -f redis \
	&& docker-php-ext-enable xdebug \
	&& docker-php-ext-enable redis
RUN echo "xdebug.remote_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.remote_enable=1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.remote_connect_back=0" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.idekey=\"PHPSTORM\"" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.remote_port=9000" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& mv /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini /usr/local/etc/php/conf.d/docker-php-ext-xdebug.disabled

RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf
RUN a2enmod rewrite

# Set locale
RUN sed -i 's/^# *\(de_DE.UTF-8\)/\1/' /etc/locale.gen
RUN locale-gen

WORKDIR ${APACHE_DOCUMENT_ROOT}
