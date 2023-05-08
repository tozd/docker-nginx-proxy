ARG IMAGE

FROM $IMAGE

COPY ./index.html /test/index.html
COPY ./test.conf /etc/nginx/sites-enabled/test.conf
