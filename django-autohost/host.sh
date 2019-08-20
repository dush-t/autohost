#!/usr/bin/env bash


# Command line arguments.
export PROJECT_NAME=$1
export PROJECT_DIR=$2
export HOST_IP=$3
export HOST_PORT=$4


HOSTING_DATA_DIR="/home/autohost/${PROJECT_NAME}_hostingdata"
sudo mkdir -p $HOSTING_DATA_DIR

sudo chown -p `whoami` $HOSTING_DATA_DIR

python3 -m venv

#-------------------------------------------------------SETUP GUNICORN--------------------------------------------------------------------

echo "Setting up gunicorn"
GUNICORN_SCRIPT="${HOSTING_DATA_DIR}/gunicorn-start.sh"

sudo apt-get install python-virtualenv
python3 -m venv $HOSTING_DATA_DIR/venv
source $HOSTING_DATA_DIR/venv/bin/activate
pip install -r $PROJECT_DIR/requirements.txt
pip install gunicorn
python $PROJECT_DIR/manage.py collectstatic

rm -rf $GUNICORN_SCRIPT
touch $GUNICORN_SCRIPT

cat >> $GUNICORN_SCRIPT <<\EOF
#!/bin/bash
EOF

cat >> $GUNICORN_SCRIPT <<EOF
source ${HOSTING_DATA_DIR}/venv/bin/activate
EOF

cat >> $GUNICORN_SCRIPT <<EOF
NAME=${PROJECT_NAME}
DJANGODIR=${PROJECT_DIR}
SOCKFILE=$HOSTING_DATA_DIR/run/gunicorn.sock
USER=root
GROUP=webdata
NUM_WORKERS=4
DJANGO_SETTINGS_MODULE=${PROJECT_NAME}.settings
DJANGO_WSGI_MODULE=${PROJECT_NAME}.wsgi
EOF

cat >> $GUNICORN_SCRIPT <<\EOF
echo "Starting $NAME as `whoami`"
source $HOSTING_DATA_DIR/venv/bin/activate
export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE
export PYTHONPATH=$DJANGODIR:$PYTHONPATH

RUNDIR=$(dirname $SOCKFILE)
test -d $RUNDIR || mkdir -p $RUNDIR

exec gunicorn ${DJANGO_WSGI_MODULE}:application \
--name $NAME \
--workers $NUM_WORKERS \
--user $USER \
--bind unix:$SOCKFILE
EOF

sudo chmod u+x $GUNICORN_SCRIPT

deactivate

#-------------------------------------------------------SETUP PROJECT ENVIRONMENT---------------------------------------------------------
echo "Installing dependencies"
sudo apt-get install nginx supervisor

echo "  "
echo "Setting up supervisor"

SUPERVISOR_CONF=/etc/supervisor/conf.d/${PROJECT_NAME}.conf
sudo rm -rf $SUPERVISOR_CONF
sudo touch $SUPERVISOR_CONF

sudo cat >> SUPERVISOR_CONF <<EOF
[program:${PROJECT_NAME}]
command = $GUNICORN_SCRIPT
user = root
stdout_file = ${HOSTING_DATA_DIR}/gunicorn-supervisor.log
redirect_stderr = true
EOF

sudo supervisorctl reread
sudo supervisorctl update

echo "  "
echo "Setting up nginx"

sudo mkdir -p ${HOSTING_DATA_DIR}/logs

NGINX_CONF=/etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf

sudo rm -rf $NGINX_CONF
sudo touch $NGINX_CONF

sudo cat >> $NGINX_CONF <<EOF

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

cat >> $NGINX_CONF <<\EOF
location / {
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Host $http_host;

proxy_redirect off;
if (!-f $request_filename) {
EOF

cat >> $NGINX_CONF <<EOF
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

