FROM heroku/heroku:16

ARG R_VERSION
ARG BUILD_NO
ARG FAKECHROOT_VER=2.19

ENV APP_DIR="/app"
ENV TOOLS_DIR="$APP_DIR/.tools"
ENV CHROOT_DIR="$APP_DIR/.root"
ENV FAKEROOT_DIR="$TOOLS_DIR/fakeroot"
ENV FAKECHROOT_DIR="$TOOLS_DIR/fakechroot"
ENV PATH="$FAKECHROOT_DIR/sbin:$FAKECHROOT_DIR/bin:$PATH"

# install prerequisites
RUN apt-get -q update \
 && apt-get -qy install rsyslog

RUN apt-get -qy install \
      xz-utils \
      fakeroot \
      autogen \
      autoconf \
      libtool \
      debootstrap \
      systemd

# "install" fakeroot (since it's not included in heroku-16 base at runtime anymore)
# see https://devcenter.heroku.com/articles/stack-packages
RUN mkdir -p $FAKEROOT_DIR/bin $FAKEROOT_DIR/lib/x86_64-linux-gnu/libfakeroot \
 && cd $FAKEROOT_DIR \
 && cp /usr/bin/fakeroot bin/fakeroot \
 && cp /usr/bin/faked-sysv bin/faked-sysv \
 && cp /usr/bin/fakeroot-sysv bin/fakeroot-sysv \
 && cp /usr/lib/x86_64-linux-gnu/libfakeroot/libfakeroot-sysv.so lib/x86_64-linux-gnu/libfakeroot/libfakeroot-sysv.so \
 && sed -i "s#/usr#/app/.tools/fakeroot#g" bin/fakeroot

# install fakechroot
RUN git clone -b "$FAKECHROOT_VER" --single-branch --depth 1 https://github.com/dex4er/fakechroot.git \
 && cd fakechroot \
 && ./autogen.sh \
 && ./configure --prefix=$FAKECHROOT_DIR \
 && make \
 && make install

# install debootstrap linux
RUN fakechroot fakeroot debootstrap --variant=fakechroot --arch=amd64 xenial $CHROOT_DIR

# fix up bashrc inside chroot
ENV BASH_RC_FILE="$CHROOT_DIR/root/.bashrc"
RUN sed -i -e s/#force_color_prompt=yes/force_color_prompt=yes/ $BASH_RC_FILE

# configure apt for R packages
RUN fakechroot fakeroot chroot $CHROOT_DIR \
     /bin/sh -c 'echo "deb http://archive.ubuntu.com/ubuntu xenial main universe" > /etc/apt/sources.list' \

 && fakechroot fakeroot chroot $CHROOT_DIR \
     /bin/sh -c 'echo "deb http://archive.ubuntu.com/ubuntu xenial-security main universe" >> /etc/apt/sources.list' \

 && fakechroot fakeroot chroot $CHROOT_DIR \
     /bin/sh -c 'echo "deb http://archive.ubuntu.com/ubuntu xenial-updates main universe" >> /etc/apt/sources.list' \

 && fakechroot fakeroot chroot $CHROOT_DIR \
     /bin/sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main" >> /etc/apt/sources.list' \

 && fakechroot fakeroot chroot $CHROOT_DIR \
     /bin/sh -c 'echo "deb http://cran.rstudio.com/bin/linux/ubuntu xenial/" >> /etc/apt/sources.list' \	     /bin/sh -c 'echo "deb https://cloud.r-project.org/bin/linux/ubuntu xenial-cran35/" >> /etc/apt/sources.list' \

 # install gpg
 && fakechroot fakeroot chroot $CHROOT_DIR \
     apt-get -qy install gnupg gpg \	     apt-get -qy install gnupg gpg \

 && fakechroot fakeroot chroot $CHROOT_DIR \
    cat /etc/resolv.conf \

 # postgres key
 && fakechroot fakeroot chroot $CHROOT_DIR \
     gpg -v --keyserver keyserver.ubuntu.com --recv-key ACCC4CF8 \

 && fakechroot fakeroot chroot $CHROOT_DIR \
     /bin/sh -c 'gpg --export ACCC4CF8 > /var/tmp/ACCC4CF8 && apt-key add /var/tmp/ACCC4CF8 && rm /var/tmp/ACCC4CF8' \

 # cran key
 && fakechroot fakeroot chroot $CHROOT_DIR \
     apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9

 && fakechroot fakeroot chroot $CHROOT_DIR \
     apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7FCC7D46ACCC4CF8 \

 && fakechroot fakeroot chroot $CHROOT_DIR \
     apt-get -q update \

 && fakechroot fakeroot chroot $CHROOT_DIR \
     apt-get -qy upgrade

# install dependencies and R
RUN fakechroot fakeroot chroot $CHROOT_DIR \
  apt-get -qy install \
    build-essential \
    curl \
    libssl1.1 \
    gfortran \
    libcairo2-dev \
    libcurl4-openssl-dev \
    libgsl0-dev \
    libssl-dev \
    libxml2-dev \
    libxt-dev \
    pkg-config \
    libcurl4-gnutls-dev \
    libgit2-dev \
    software-properties-common \
    r-base-core=${R_VERSION}* \
    r-base-dev=${R_VERSION}* \
    # r-cran-mgcv \
    r-cran-rpart \
    r-cran-survival \
    r-cran-matrix=1.2-16* \
    r-doc-html=${R_VERSION}* \
    r-recommended=${R_VERSION}*

    # install pandoc
    RUN fakechroot fakeroot chroot $CHROOT_DIR \
      /bin/sh -c 'curl -s -L https://github.com/jgm/pandoc/releases/download/1.19.2.1/pandoc-1.19.2.1-1-amd64.deb -o pandoc.deb && dpkg -i pandoc.deb && rm pandoc.deb'

    # install devtools and curl
    RUN fakechroot fakeroot chroot $CHROOT_DIR \
      /usr/bin/R -e "install.packages(c('devtools','curl'))"	  /usr/bin/R -e "install.packages('openssl', INSTALL_opts = '--no-test-load')"

    RUN fakechroot fakeroot chroot $CHROOT_DIR \
      nm -a /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1

    # install devtools and curl
    RUN fakechroot fakeroot chroot $CHROOT_DIR \
      /usr/bin/R -e "install.packages('curl')"

    # install dash
    RUN fakechroot fakeroot chroot $CHROOT_DIR \
     /usr/bin/R -e "install.packages('openssl', INSTALL_opts = '--no-test-load')"	/usr/bin/R -e "r <- getOption('repos'); r['CRAN'] <- 'http://cloud.r-project.org'; options(repos=r, Ncpus=2); install.packages(c('devtools', 'callr', 'data.table', 'plotly', 'ggplot2', 'scales', 'httr', 'jsonlite',  'magrittr', 'digest', 'viridisLite', 'base64enc', 'htmltools', 'htmlwidgets', 'tidyr', 'hexbin', 'RColorBrewer', 'dplyr', 'tibble', 'lazyeval', 'rlang', 'crosstalk', 'purrr', 'promises', 'R6', 'shiny', 'assertthat', 'glue', 'pkgconfig', 'Rcpp', 'tidyselect', 'BH', 'plogr', 'gtable', 'MASS', 'mgcv', 'reshape2', 'withr', 'lattice', 'yaml', 'curl', 'mime', 'openssl', 'later', 'labeling', 'munsell', 'cli', 'crayon', 'fansi', 'pillar', 'ellipsis', 'stringi', 'vctrs', 'lifecycle', 'nlme', 'Matrix', 'colorspace', 'askpass', 'utf8', 'plyr', 'stringr', 'httpuv', 'xtable', 'sourcetools', 'backports', 'zeallot', 'sys', 'fiery', 'uuid', 'future', 'reqres', 'globals', 'listenv', 'urltools', 'brotli', 'xml2', 'webutils', 'codetools', 'triebeard')); remotes::install_github('plotly/dashR', upgrade=TRUE)"
