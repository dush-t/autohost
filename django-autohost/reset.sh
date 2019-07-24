export PROJECT_NAME=$1

echo "Removing all traces of your website..."

sudo rm -rf /srv/$PROJECT_NAME
sudo rm -rf /etc/nginx/sites-enabled/${PROJECT_NAME}.nginxconf
sudo rm -rf /etc/supervisor/conf.d/${PROJECT_NAME}.conf

echo "Done"
