FROM nginx:alpine

COPY nginx.conf /etc/nginx/templates/nginx.conf.template

ENV API_KEY=default

CMD ["/bin/sh", "-c", "envsubst '$API_KEY' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf && nginx -g 'daemon off;'"]