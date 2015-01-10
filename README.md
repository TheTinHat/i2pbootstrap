I2P Bootstrap
------------

A simple script to automate much of the setup process when creating a high bandwidth I2P router on a VPS. 

This script was tested on a fresh Digital Ocean Debian Wheezy server and worked perfectly. If 
you plan on using this on an existing server, definitely read through the script and understand 
the changes that will be made, as it will adjust your SSH settings as well as your firewall 
rules, among other things. Lastly, don't blame me if this somehow borks your machine, as it's 
meant to go on a fresh Debian 7 server. You will also need to create a separate user with sudo 
privileges before running this script, or you'll be locked out of the machine (it disables root 
login).


To use it just download the script and execute it

`wget https://raw.githubusercontent.com/TheTinHat/i2pbootstrap/master/i2p_bootstrap.sh`
`bash i2p_bootstrap.sh`
