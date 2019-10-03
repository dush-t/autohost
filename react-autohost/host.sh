#!/bin/bash

export REACT_PATH=$1
export HOST_IP=$2
export HOST_PORT=$3

echo "Please select the appropriate option (press 1 or 2) - "
echo "	1. My server is not serving anything else. This React-app is the only thing I'll be deploying. (Recommended for most users)"
echo "	2. My server is serving another web-app and I want to deploy this react-app on the same url base url with a different path"
echo ">"
read choice

sudo apt-get install nginx

if [[ "${choice}" == "2" ]]
then
	echo "Please enter the subdomain that you'd like your app to be served at."
	echo "For example if your domain is example.com and you want your app to be served at example.com/myApp, enter /myApp"
	read HOST_SUB_URL
	echo "Enter the path of the current nginx file that you're using (include the file extension)"
	read NGINXCONF_PATH
	
	echo "Setting up nginx..."
	

	#touch /etc/nginx/sites-enabled/${NGINXCONF_NAME}.nginxconf
	
	touch nginxLocationBlock.txt
	
	cat >> nginxLocationBlock <<-EOF
	
		location ${HOST_SUB_URL} {
			expires 1h;
			autoindex on;
			alias ${REACT_PATH}/build;
			try_files $uri $uri/ $uri.html /index.html;
		}
	
	EOF
	
	sudo sed "/<\location>/i $(<nginxLocationBlock.txt)" ${NGINXCONF_PATH} # Have a bad feeling about this, hope it works.

elif [[ ${choice} == "1" ]]
then
	echo "Give a name to your project - "
	read PROJECT_NAME
	echo "Sit back while I deploy your react app for you."
	
	echo "Setting up nginx..."
	
	sudo rm -rf /etc/nginx/sites-enabled/${PROJECT_NAME}
	touch /etc/nginx/sites-enabled/${PROJECT_NAME}
	
	cat >> /etc/nginx/sites-enabled/${PROJECT_NAME} <<-EOF
	
	server {
		listen ${HOST_PORT} default_server;
		root ${REACT_PATH}/build;
		server_name ${HOST_IP};
		index index.html index.htm;
		location / {
		}
	}
	
	EOF
fi


echo "Building your React project"
cd ${REACT_PATH}
node scripts/build.js


echo "Restarting nginx..."
sudo service nginx restart
echo "Done!"
echo "Your react app is online at ${HOST_IP}:${HOST_PORT}"

