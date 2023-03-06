FROM perl:5.36.0
ADD . /app
WORKDIR /app
RUN cpanm -n .
ENTRYPOINT ["pickaxe"]
