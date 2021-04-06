FROM nginx

EXPOSE 80

RUN apt update && apt install -y wget

COPY temp/*.svg /usr/share/nginx/html/
COPY temp/images/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY temp/images/health/static_page_health_check.sh /usr/bin
COPY temp/index_cdf.html /usr/share/nginx/html/index.html
