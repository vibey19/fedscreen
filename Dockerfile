# One command to rebuild the whole project: the pipeline and the dashboard.
#
#   docker build -t fedscreen .
#   docker run --rm -v "$PWD/_site:/project/_site" fedscreen
#
# Three things are pinned here so a build today gives the same answers as a
# build next year: the R version (the base image tag), the package versions
# (renv.lock) and the Quarto version (below).

FROM rocker/r-ver:4.5.2

# renv.lock points at CRAN, which only ships source packages for Linux, so a
# plain restore would compile all 89 of them. Posit's public package manager
# serves ready-built packages for Ubuntu 24.04 ("noble"), which is what the
# base image above is built on. Minutes instead of most of an hour.
#
# If the base image tag changes, check that the Ubuntu name still matches.
ENV RENV_CONFIG_REPOS_OVERRIDE=https://p3m.dev/cran/__linux__/noble/latest

# System libraries the R packages need. This list is not guesswork: renv
# prints the system packages it is missing before it installs anything, and
# this is what it asked for. The -dev packages are here because a package
# whose pinned version is no longer the current one has no ready-built copy
# and is compiled instead, which needs the headers.
#
# renv also asks for pandoc, which knitr and rmarkdown use to turn markdown
# into a document. Quarto brings its own copy, so installing Ubuntu's as well
# would just be a second one.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       cmake \
       curl \
       libcurl4-openssl-dev \
       libglpk-dev \
       libicu-dev \
       libssl-dev \
       libuv1-dev \
       libxml2-dev \
       xz-utils \
  && rm -rf /var/lib/apt/lists/*

# Quarto is a separate program, not an R package, so renv does not install
# it. TARGETARCH is set by the build itself, so this works on both Intel and
# Apple Silicon machines.
ARG QUARTO_VERSION=1.10.19
ARG TARGETARCH
RUN curl -fsSL -o /tmp/quarto.deb \
      "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${TARGETARCH}.deb" \
  && dpkg --install /tmp/quarto.deb \
  && rm /tmp/quarto.deb

WORKDIR /project

# The packages are installed in their own layer, before any project code is
# copied in, so editing an R file does not reinstall all of them.
COPY renv.lock .Rprofile ./
COPY renv/activate.R renv/settings.json renv/
RUN Rscript -e 'renv::restore()'

# Only what the pipeline, the tests and the dashboard need. Naming the
# folders instead of copying everything keeps local notes and caches out of
# the image.
COPY R/ R/
COPY tests/ tests/
COPY schema/ schema/
COPY data/aggregates/ data/aggregates/
COPY data/combined/ data/combined/
COPY dashboard/ dashboard/
COPY _targets.R _quarto.yml run.sh ./

CMD ["./run.sh"]
