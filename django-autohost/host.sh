#!/bin/bash

export PROJECT_NAME=$1
export PROJECT_DIR=$2
export HOST_IP=$3
export HOST_PORT=$4

HOSTING_DIR=/home/autohost/${PROJECT_NAME}_hostingdata

echo "Saving hosting files at: ${HOSTING_DIR}"

sudo mkdir -p $HOSTING_DIR

#-------------------------------------------------------SETUP GUNICORN--------------------------------------------------------------------

echo "Setting up gunicorn..."
GUNICORN_SCRIPT=${HOSTING_DIR}/gunicorn-start.sh

sudo rm -rf $GUNICORN_SCRIPT
sudo touch $GUNICORN_SCRIPT

cat >> $GUNICORN_SCRIPT << \EOF
#!bin/bash
EOF

cat >> $GUNICORN_SCRIPT <<EOF
NAME=${PROJECT_NAME}
DJANGODIR=${PROJECT_DIR}
SOCKFILE=${HOSTING_DIR}/run/gunicorn.sock
USER=root
GROUP=webdata
NUM_WORKERS=4
DJANGO_SETTINGS_MODULE=${PROJECT_NAME}.settings
DJANGO_WSGI_MODULE=${PROJECT_NAME}.wsgi
EOF

cat >> $GUNICORN_SCRIPT <<\EOF
echo 'Starting $NAME as `whoami`'
EOF

cat >> $GUNICORN_SCRIPT <<EOF
source ${HOSTING_DIR}/venv/bin/activate

cat  >> $GUNICORN_SCRIPT <<\EOF
echo "Starting $NAME as `whoami`"
source /srv/${NAME}/venv/bin/activate
export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE
export PYTHONPATH=$DJANGODIR:$PYTHONPATH
EOF

cat >> $GUNICORN_SCRIPT <<EOF
RUNDIR=${HOSTING_DIR}/run
EOF

cat >> $GUNICORN_SCRIPT <<\EOF
test -d $RUNDIR || mkdir -p $RUNDIR
exec gunicorn ${DJANGO_WSGI_MODULE}:application \
  --name $NAME \
  --workers $NUM_WORKERS \
  --user $USER \
  --bind=unix:$SOCKFILE
EOF

sudo chmod u+x $GUNICORN_SCRIPT

#-------------------------------------------------------SETUP PROJECT ENVIRONMENT---------------------------------------------------------
echo "Setting up virtual environment..."
python3 -m venv $HOSTING_DIR/venv
source $HOSTING_DIR/venv/bin/activate
pip3 install -r ${PROJECT_DIR}/requirements.txt
pip3 install gunicorn

python3 ${PROJECT_DIR}/manage.py collectstatic

deactivate

#--------------------------------------------------------------SETUP SUPERVISOR----------------------------------------------------------------
echo "Installing dependencies..."
sudo apt-get install nginx
sudo apt-get install supervisor

echo "  "

echo "Setting up supervisor..."
echo $PROJECT_NAME.conf

$SUPERVISOR_CONF=/etc/supervisor/conf.d/${PROJECT_NAME}.conf

sudo rm -rf $SUPERVISOR_CONF
sudo touch $SUPERVISOR_CONF

sudo cat >> $SUPERVISOR_CONF <<EOF
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
NGINX_CONF=/etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf

sudo rm -rf $NGINX_CONF
sudo touch $NGINX_CONF

sudo cat >> $NGINX_CONF <<EOF

upstream ${PROJECT_NAME}_app_server {
  server unix:${HOSTING_DIR}/run/gunicorn.sock fail_timeout=0;
}

server {
  listen $HOST_PORT;
  server_name $HOST_IP;

  client_max_body_size 4G;

  access_log ${HOSTING_DIR}/logs/nginx-access.log;
  error_log ${HOSTING_DIR}/logs/nginx-error.log

  location /static/ {
    alias ${PROJECT_DIR}/static/;
  }

  location /media/ {
    alias $PROJECT_DIR/media/;
  }
EOF


cat >> /etc/nginx/sites-enabled/$PROJECT_NAME.nginxconf <<EOF
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
echo "Finishing up..."

sudo service nginx restart
sudo service supervisor restart

echo "  "
echo "Your django project is online on ${HOST_IP}:${HOST_PORT}"
