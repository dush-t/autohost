#!/bin/bash

# Get the following variables from arguments in the command line.
export PROJECT_NAME=$1 # Name of project.
export PROJECT_DIR=$2 # Path to project.
export HOST_IP=$3 # Hosting ip
export HOST_PORT=$4 # Port

echo "Setting up gunicorn..."
GUNICORN_SCRIPT="${PROJECT_DIR}/gunicorn-start.sh"

rm -rf $GUNICORN_SCRIPT
touch $GUNICORN_SCRIPT

cat >> $GUNICORN_SCRIPT <<\EOF
#!/bin/bash
EOF

#-------------------------------------------------------------------SETUP GUNICORN--------------------------------------------------------------------

cat >> $GUNICORN_SCRIPT <<EOF
NAME=${PROJECT_NAME}
DJANGODIR=${PROJECT_DIR}
SOCKFILE=/srv/${PROJECT_NAME}/run/gunicorn.sock
USER=root
GROUP=webdata
NUM_WORKERS=4
DJANGO_SETTINGS_MODULE=${PROJECT_NAME}.settings
DJANGO_WSGI_MODULE=${PROJECT_NAME}.wsgi
EOF

cat >> $GUNICORN_SCRIPT <<\EOF
echo "Starting $NAME as `whoami`"
source $DJANGODIR/venv/bin/activate
export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE
export PYTHONPATH=$DJANGODIR:$PYTHONPATH

RUNDIR=$(dirname $SOCKFILE)
test -d $RUNDIR || mkdir -p $RUNDIR

exec gunicorn ${DJANGO_WSGI_MODULE}:application \
  --name $NAME\
  --workers $NUM_WORKERS \
  --user $USER \
  --group www-data
  --bind=unix:$SOCKFILE

EOF

sudo chmod u+x $GUNICORN_SCRIPT


python3 -m venv $PROJECT_DIR/venv
source $PROJECT_DIR/venv/bin/activate
pip install -r $PROJECT_DIR/requirements.txt
python $PROJECT_DIR/manage.py collectstatic

deactivate


#---------------------------------------------------------------SETUP PROJECT ENVIRONMENT--------------------------------------------------------------

echo "Installing dependencies..."
sudo apt-get install nginx supervisor

echo "  "
echo "Setting up supervisor"
echo $PROJECT_NAME.conf

SUPERVISOR_CONF=/etc/supervisor/conf.d/${PROJECT_NAME}.conf
sudo rm -rf $SUPERVISOR_CONF
sudo touch $SUPERVISOR_CONF
sudo cat >> $SUPERVISOR_CONF <<EOF
[program:$PROJECT_NAME]
command = $GUNICORN_SCRIPT
user = root
stdout_file = $PROJECT_DIR/gunicorn-supervisor.log
redirect_stderr = true
EOF

sudo supervisorctl reread
sudo supervisorctl update

echo "  "
echo "Setting up nginx"

sudo mkdir -p ${PROJECT_DIR}/logs
NGINX_CONF=/etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf

sudo rm -rf $NGINX_CONF
sudo touch $NGINX_CONF

sudo cat >> $NGINX_CONF <<EOF

upstream ${PROJECT_NAME}_app_server {
  server unix:$PROJECT_DIR/run/${PROJECT_NAME}.sock fail_timeout=0;
}

server {

  listen $HOST_PORT;
  server_name $HOST_IP;

  client_max_body_size 4G;

  access_log $PROJECT_DIR/logs/nginx-access.log;
  error_log $PROJECT_DIR/logs/nginx-error.log;

  location /static/ {
    alias $PROJECT_DIR/static/;
  }

  location /media/ {
    alias $PROJECT_DIR/media/;
}
EOF

cat >> /etc/nginx/sites-enabled/$PROJECT_NAME.nginxconf <<\EOF

  location / {
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header Host $http_host;

          proxy_redirect off;
        if (!-f $request_filename) {
EOF

cat >> /etc/nginx/sites-enabled/$PROJECT_NAME.nginxconf <<EOF

            proxy_pass http://${PROJECT_NAME}_app_server;
            break;
        }
    }

    # Error pages
    error_page 500 502 503 504 /500.html;
    location = /500.html {
        root ${SCRIPT_PATH}/static/;
    }
}

EOF

echo "  "
echo "Finishing up..."

sudo service nginx restart
sudo service supervisor restart

echo "  "
echo "Your django project is online on ${HOST_IP}:${HOST_PORT}" 

