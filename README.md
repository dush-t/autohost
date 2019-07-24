# Autohost
Shell scripts for quick production deployment of web apps.

## For Django - 

1. Clone this repository to your local machine/server
2. Navigate to django-autohost directory and give host.sh executable permissions by `sudo chmod +x ./host.sh`
3. Run `sudo ./host.sh <ProjectName> /path/to/project/root/directory "ip_address" "port"`

Your project root is the folder which contains the manage.py file. The path to project root should be absolute.
For example, if I had a project named MyProject at 
/django/MyProject and wanted to host it locally on port 8080, I would use - 

`sudo ./host.sh MyProject /django/MyProject "localhost" "8000"` (Notice the quotation marks over IP address and port)

This would store hosting-related info with the identifier "MyProject" (yes, it is necessary to use the same name
as your django project name). After running that command, you will be able to view your website at localhost:8000. Don't
forget the sudo, this script requires root permissions to place config files in the right directories.

#### Note: If you want to host at localhost, make sure you write "localhost" there and not "127.0.0.1". Nginx will have issues problems if you write 127.0.0.1.

#### Note -
This script will use nginx and gunicorn (with 4 process workers) to host your web app. The script is ONLY for hosting, and not for managing your project.
This means once hosted, you will still need to manage your app. Things like making migrations and collectstatic still need to be 
done manually (the script will collect static for you once, at the time of running).

When the script completes it's job, you'll be able to find your project at `/srv/<ProjectName>/<ProjectName>`. Only changes there
will ultimately be reflected on the hosted app.

#### How to "un-host" - 
To remove your webapp from your server, do the following - 
1. Navigate to django-autohost directory and give host.sh executable permissions by `sudo chmod +x ./remove.sh`
2. Execute `./remove.sh <ProjectName>`, where <ProjectName> is the name of the project that you used earlier when hosting it.
3. You're done.