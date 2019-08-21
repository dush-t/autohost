#!/bin/bash

export PROJECT_NAME=$1
export PROJECT_DIR=$2
export HOST_IP=$3
export HOST_PORT=$4

HOSTING_DIR="/home/autohost/${PROJECT_NAME}_hostingdata"

echo "Saving hosting files at: ${HOSTING_DIR}"

sudo mkdir -p "$HOSTING_DIR"

sudo chgrp www-data  "$HOSTING_DIR"
#-------------------------------------------------------SETUP GUNICORN--------------------------------------------------------------------

echo "Setting up gunicorn..."

sudo rm -rf ${HOSTING_DIR}/gunicorn-start.sh
sudo touch ${HOSTING_DIR}/gunicorn-start.sh

cat >> ${HOSTING_DIR}/gunicorn-start.sh << \EOF
#!bin/bash
EOF

cat >> ${HOSTING_DIR}/gunicorn-start.sh <<EOF
NAME=${PROJECT_NAME}
DJANGODIR=${PROJECT_DIR}
SOCKFILE=${HOSTING_DIR}/run/gunicorn.sock
USER=root
GROUP=www-data
NUM_WORKERS=4
DJANGO_SETTINGS_MODULE=${PROJECT_NAME}.settings
DJANGO_WSGI_MODULE=${PROJECT_NAME}.wsgi
EOF

cat >> ${HOSTING_DIR}/gunicorn-start.sh <<\EOF
echo "Starting $NAME as `whoami`"
EOF

cat >> ${HOSTING_DIR}/gunicorn-start.sh <<EOF
source ${HOSTING_DIR}/venv/bin/activate
EOF

cat  >> ${HOSTING_DIR}/gunicorn-start.sh <<\EOF
echo "Starting $NAME as $(whoami)"
source /srv/${NAME}/venv/bin/activate
export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE
export PYTHONPATH=$DJANGODIR:$PYTHONPATH
EOF

cat >> ${HOSTING_DIR}/gunicorn-start.sh <<EOF
RUNDIR=${HOSTING_DIR}/run
EOF

cat >> ${HOSTING_DIR}/gunicorn-start.sh <<\EOF
test -d $RUNDIR || mkdir -p $RUNDIR
exec gunicorn ${DJANGO_WSGI_MODULE}:application \
  --name $NAME \
  --workers $NUM_WORKERS \
  --user $USER \
  --group $GROUP
  --bind=unix:$SOCKFILE
EOF

sudo chmod u+x ${HOSTING_DIR}/gunicorn-start.sh

#-------------------------------------------------------SETUP PROJECT ENVIRONMENT---------------------------------------------------------
echo "Setting up virtual environment..."
python3 -m venv "$HOSTING_DIR"/venv
source "$HOSTING_DIR"/venv/bin/activate
pip3 install -r "${PROJECT_DIR}"/requirements.txt
pip3 install gunicorn

python3 "${PROJECT_DIR}"/manage.py collectstatic

deactivate

#--------------------------------------------------------------SETUP SUPERVISOR----------------------------------------------------------------
echo "Installing dependencies..."
sudo apt-get install nginx
sudo apt-get install supervisor

echo "  "

echo "Setting up supervisor..."
echo "$PROJECT_NAME".conf

sudo rm -rf /etc/supervisor/conf.d/${PROJECT_NAME}.conf
sudo touch /etc/supervisor/conf.d/${PROJECT_NAME}.conf

sudo cat >> /etc/supervisor/conf.d/${PROJECT_NAME}.conf <<EOF
[program:$PROJECT_NAME]
command = $GUNICORN_SCRIPT
user = root
stdout_file = ${HOSTING_DATA_DIR}/logs/gunicorn-supervisor.log
redirect_stderr = true
EOF

sudo supervisorctl reread
sudo supervisorctl update

echo "  "

#--------------------------------------------------------------SETUP NGINX----------------------------------------------------------------

echo "Setting up nginx"

sudo mkdir -p ${HOSTING_DATA_DIR}/logs

sudo rm -rf /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf
sudo touch /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf

sudo cat >> /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf <<EOF
upstream ${PROJECT_NAME}_app_server {
server unix:${HOSTING_DATA_DIR}/run/${PROJECT_NAME}.sock fail_timeout=0;
}
server {
listen $HOST_PORT;
server_name $HOST_IP;
client_max_body_size 4G;
access_log $HOSTING_DATA_DIR/logs/nginx-access.log;
error_log $HOSTING_DATA_DIR/logs/nginx-error.log;
location /static/ {
alias $PROJECT_DIR/static/;
}
location /media/ {
alias $PROJECT_DIR/media/;
}
EOF

cat >> /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf <<\EOF
location / {
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Host $http_host;
proxy_redirect off;
if (!-f $request_filename) {
EOF

cat >> /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf <<EOF
proxy_pass http://${PROJECT_NAME}_app_server;
break;
}
}
# Error pages
error_page 500 502 503 504 /500.html;
location = /500.html {
root ${PROJECT_DIR}/static/;
}
}
EOF

echo "  "

sudo service nginx restart
sudo service supervisor restart

echo "  "
echo "Your django project is online on ${HOST_IP}:${HOST_PORT}"

echo "  "
echo "Finishing up..."

sudo service nginx restart
sudo service supervisor restart

echo "  "
echo "Your django project is online on ${HOST_IP}:${HOST_PORT}"
