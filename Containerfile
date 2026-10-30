FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*

COPY certs/cert.pem /etc/ssl/certs/cert.pem
COPY certs/key.pem /etc/ssl/private/key.pem
COPY default.conf /etc/nginx/sites-available/default

COPY html /var/www/html

EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]