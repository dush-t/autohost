#!/bin/bash

export PROJECT_NAME=$1
export PROJECT_DIR=$2
export HOST_IP=$3
export HOST_PORT=$4

sudo mkdir /srv/$PROJECT_NAME
sudo mkdir /srv/$PROJECT_NAME/run
sudo mkdir /srv/$PROJECT_NAME/logs
sudo touch /srv/$PROJECT_NAME/logs/gunicorn-supervisor.log
sudo touch /srv/$PROJECT_NAME/logs/nginx-access.log
sudo touch /srv/$PROJECT_NAME/logs/nginx-error.log

sudo cp -r $PROJECT_DIR /srv/$PROJECT_NAME

#-------------------------------------------------------------------SETUP GUNICORN--------------------------------------------------------------------

echo "Setting up gunicorn..."

touch /srv/${PROJECT_NAME}/gunicorn-start.sh

cat >> /srv/${PROJECT_NAME}/gunicorn-start.sh <<\EOF
#!/bin/bash
EOF

cat >> /srv/${PROJECT_NAME}/gunicorn-start.sh <<EOF
NAME="${PROJECT_NAME}"
DJANGODIR=/srv/${PROJECT_NAME}/${PROJECT_NAME}
SOCKFILE=/srv/${PROJECT_NAME}/run/gunicorn.sock
USER=root
GROUP=webdata
NUM_WORKERS=4
DJANGO_SETTINGS_MODULE=${PROJECT_NAME}.settings
DJANGO_WSGI_MODULE=${PROJECT_NAME}.wsgi
EOF

cat >> /srv/${PROJECT_NAME}/gunicorn-start.sh <<\EOF
echo "Starting $NAME as `whoami`"
source /srv/${NAME}/venv/bin/activate
export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE
export PYTHONPATH=$DJANGODIR:$PYTHONPATH

RUNDIR=$(dirname $SOCKFILE)
test -d $RUNDIR || mkdir -p $RUNDIR

exec gunicorn ${DJANGO_WSGI_MODULE}:application \
  --name $NAME \
  --workers $NUM_WORKERS \
  --user $USER \
  --bind=unix:$SOCKFILE

EOF

sudo chmod u+x /srv/$PROJECT_NAME/gunicorn-start.sh



#---------------------------------------------------------------SETUP PROJECT ENVIRONMENT--------------------------------------------------------------

# cd /srv/$PROJECT_NAME
python3 -m venv /srv/$PROJECT_NAME/venv
source /srv/$PROJECT_NAME/venv/bin/activate
pip install -r /srv/$PROJECT_NAME/$PROJECT_NAME/requirements.txt
pip install gunicorn

python $PROJECT_NAME/manage.py collectstatic

deactivate


#--------------------------------------------------------------SETUP SERVER-------------------------------------------------------------------------

echo "installing dependencies..."
sudo apt-get install nginx
sudo apt-get install supervisor
echo "  "

echo "Setting up supervisor"
echo $PROJECT_NAME.conf

sudo rm -rf /etc/supervisor/conf.d/$PROJECT_NAME.conf
touch /etc/supervisor/conf.d/$PROJECT_NAME.conf

sudo cat >> /etc/supervisor/conf.d/$PROJECT_NAME.conf <<EOF
[program:$PROJECT_NAME]
command = /srv/$PROJECT_NAME/gunicorn-start.sh
user = root
stdout_logfile = /srv/${PROJECT_NAME}/logs/gunicorn-supervisor.log
redirect_stderr = true
EOF

sudo supervisorctl reread
sudo supervisorctl update

echo "  "
echo "Setting up nginx"

sudo rm -rf /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf
touch /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf

sudo cat >> /etc/nginx/sites-enabled/$PROJECT_NAME.nginxconf <<EOF

upstream ${PROJECT_NAME}_app_server {
  server unix:/srv/${PROJECT_NAME}/run/gunicorn.sock fail_timeout=0;
}

server {

	listen $HOST_PORT;
	server_name $HOST_IP;
	
	client_max_body_size 4G;
	
	access_log /srv/${PROJECT_NAME}/logs/nginx-access.log;
	error_log /srv/${PROJECT_NAME}/logs/nginx-error.log;
	
	location /static/ {
		alias	/srv/$PROJECT_NAME/$PROJECT_NAME/static/;
	}
	
	location /media/ {
		alias	/srv/$PROJECT_NAME/$PROJECT_NAME/media;
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

