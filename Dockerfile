FROM php:7.4.18-apache
ENV TIMEZONE Europe/Berlin
ARG APACHE_DOCUMENT_ROOT

MAINTAINER Steven Zemelka <steven.zemelka@gmail.com>

### heavy installs first, so they will be cached on further builds if only configs further down are changed

RUN apt-get update && apt-get install -y --no-install-recommends gnupg vim git curl wget unzip tmux htop sudo libpq-dev zlib1g-dev libicu-dev \
    g++ libgmp-dev libmcrypt-dev libbz2-dev libpng-dev libjpeg62-turbo-dev \
    libfreetype6-dev libfontconfig \
    librabbitmq-dev libssl-dev gcc make autoconf libc-dev pkg-config \
    default-mysql-client libmcrypt-dev libpq-dev libmemcached-dev zsh locales libzip-dev libxml2-dev \
     && rm -rf /var/lib/apt/lists/*

# Type docker-php-ext-install to see available extensions
RUN docker-php-ext-install -j$(nproc) iconv pdo pgsql pdo_pgsql mysqli pdo_mysql intl bcmath gmp bz2 zip soap gd opcache \
    && apt-get clean

RUN docker-php-ext-configure gd --with-freetype --with-jpeg

# install php modules
RUN pecl install xdebug-3.1.5 \
	&& pecl install pcov \
	&& pecl install amqp \
	&& pecl install -o -f redis \
	&& docker-php-ext-enable xdebug \
	&& docker-php-ext-enable amqp \
	&& docker-php-ext-enable redis \
	&& docker-php-ext-enable soap \
	&& docker-php-ext-enable pcov

# NVM & NPM
RUN mkdir /usr/local/nvm
ENV NVM_DIR /usr/local/nvm
ENV NODE_VERSION 12.18.2
RUN curl https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

RUN ln -s $NVM_DIR/versions/node/v$NODE_VERSION/bin/node /usr/local/bin/node \
	&& ln -s $NVM_DIR/versions/node/v$NODE_VERSION/bin/npm /usr/local/bin/npm \
	&& ln -s $NVM_DIR/versions/node/v$NODE_VERSION/bin/yarn /usr/local/bin/yarn

### configs and single packages installation

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
	&& composer self-update 2.4.4

# Install Symfony CLI binary
RUN wget https://get.symfony.com/cli/installer -O - | bash &&  mv /root/.symfony5/bin/symfony /usr/local/bin/symfony

# install yarn and deployer globally
ENV COMPOSER_ALLOW_SUPERUSER 1
RUN composer global require deployer/deployer
RUN npm install -g yarn

# Install oh-my-zsh and set ZSH as default shell
RUN wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true \
	&& chsh -s $(which zsh)

ADD ./.zshrc /root/.zshrc

# Set Xdebug 3 settings
RUN echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.mode=develop,debug" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.idekey=\"PHPSTORM\"" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& echo "xdebug.remote_port=9003" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
	&& mv /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini /usr/local/etc/php/conf.d/docker-php-ext-xdebug.disabled

# Add opcache config
ADD opcache.ini /usr/local/etc/php/conf.d/opcache.ini

RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && a2enmod rewrite

# Set locale and timezone
RUN sed -i 's/^# *\(de_DE.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
	&& ln -snf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && echo ${TIMEZONE} > /etc/timezone \
	&& printf '[PHP]\ndate.timezone = "%s"\n', ${TIMEZONE} > /usr/local/etc/php/conf.d/tzone.ini \
	&& "date"

# Set php.ini values
RUN cp /usr/local/etc/php/php.ini-development /usr/local/etc/php/php.ini \
    && sed -i -e "s/^ *memory_limit.*/memory_limit = -1/g" /usr/local/etc/php/php.ini

WORKDIR /var/www
