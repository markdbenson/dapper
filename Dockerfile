# Dapper in a container: no Perl needed on the host.
#
#   docker run --rm -v "$PWD":/site ghcr.io/markdbenson/dapper build
#   docker run --rm -v "$PWD":/site -p 8000:8000 ghcr.io/markdbenson/dapper serve

FROM perl:5.40 AS build
WORKDIR /src
COPY . .
RUN cpanm --notest --installdeps . \
 && perl Makefile.PL && make && make install

FROM perl:5.40-slim
COPY --from=build /usr/local/lib/perl5/site_perl /usr/local/lib/perl5/site_perl
COPY --from=build /usr/local/bin/dapper /usr/local/bin/dapper
WORKDIR /site
EXPOSE 8000
ENTRYPOINT ["dapper"]
CMD ["--help"]
