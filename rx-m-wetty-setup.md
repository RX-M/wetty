![RX-M LLC](https://rx-m.com/rxm-cnc.svg)


# wetty setup for AWS


## What is wetty?

Wetty is an open source implementation of web browsing to a Linux TTY terminal (we-tty). It listens on a
designated port (3000 is the default) and accepts a Linux user login (username/password) through a browser 
interface. It uses HTTP or HTTPS to connect and then upgrades to WebSocket for performance. The wetty 
service then connects to an sshd service on the back side (often via localhost), extending ssh access 
to the client over the web.


## Why not use SSH directly?

In enterprise environments, access to port 22 (ssh) may be denied, often by more than one system (e.g.,
zscaler, iptables, gateways, etc.). Some systems block ssh even when found on other ports. In order to 
allow students to access EC2 instances on AWS in this type of environment, we need a workaround.


## How does wetty help?

It is rare that enterprises block access to an AWS IPs, even corporate employees need to browse
(often reaching commercial or public servers on EC2 using HTTP/S on ports 80/443). Wetty thus 
allows corporate students to gain terminal access to our AWS EC2 Lab VMs over HTTP/S. Another 
option is Guacamole, but this requires a fairly complex setup. 


## How is wetty run in a lab environment?

We simply run wetty on every student system. This involes either executing an installer script or
installing docker and running the wetty container. This can be done with Ansible, Terraform or
an EC2 Data Script. Caveats:

- Unlike normal RX-M lab environments which use ssh keys, a password must be set (one password can be used for all of the lab systems)
- X11 forwarding does not work over wetty (popup auth windows and the like will not work)
- SFTP does not work over wetty, wetty is not ssh, it is WebSocket based


## Setup on the AWS Linux box (ubuntu)

The easiest way to complete setup is to:

1. Open the EC2 Console and start the "Launch instance" process.
2. Navigate to the Advanced details section.
3. Paste an install script into the User data field.

The AWS console will then automatically run the script on each system launched.

Script to run wetty with TLS on port 443:

```
wget -O - https://get.docker.com | sh
PASS="${1:-rx-m$(date +%Y%m%d)}"
echo "ubuntu:${PASS}" | chpasswd
rm /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
systemctl restart ssh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout my-untrusted.key \
  -out my-untrusted.cert -subj "/C=US/ST=State/L=City/O=Organization/CN=rx-m.com"
docker run -d --net=host --restart always -v $(pwd)/my-untrusted.cert:/tmp/wetty.cert:ro \
  -v $(pwd)/my-untrusted.key:/tmp/wetty.key:ro wettyoss/wetty -p 443 --force-ssh \
  --ssl-cert /tmp/wetty.cert --ssl-key /tmp/wetty.key
```

To access the system Browser to URL:  `https://<pub-ip>/wetty`

Login with credentials: `ubuntu/rx-myyyymmdd` (password defaults to rx-m and the year, month, 
day of system launch), setting the password to something less predictable in the script is advised.

More info below:


### 1 - Typical repo update

After connecting to an AWS instance, we can bring repos up-to-date:

```
sudo apt update
```


### 2 - Install docker

Typical docker community edition install:

```
sudo apt install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
```

Exit the session, then re-establish to update the user to the docker group - as always.


### 3 - Create a pssword and/or user for login

You can either let users login as "ubuntu" or create a new user name. Regardless, you will need to provide
a password credential for the account.

For user "ubuntu":

```
sudo passwd ubuntu
```

For a new user:

```
sudo adduser student
```


### 5 - Modify sshd to accept password credential

> N.B. This is the default and not needed:

Edit the file /etc/ssh/sshd_config to allow password logins:

```
PasswordAuthentication yes
```

> N.B. You can also just delete this file.

And kill an override in an sshd daemon directory: /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
(Comment out the line or change the no to yes)

```
#PasswordAuthentication no
```

And restart sshd:

```
sudo systemctl reload ssh
```


### 6 - Run the wetty container

The docker container for wetty has some tricky switches:

```
docker run -d --net=host --restart always wettyoss/wetty -p 80 --force-ssh

```


#### 6.1 - Running wetty over TLS (port 443)

To run wetty using an untrusted certificate (not all enterprises will allow this):

First create the untrusted cert:

```
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout my-untrusted.key \
  -out my-untrusted.cert \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=rx-m.com"
```

Then use a different command to launch the container:

```
docker run -d \
  --name wetty \
   --net=host \
  --restart always \
  -v $(pwd)/my-untrusted.cert:/tmp/wetty.cert:ro \
  -v $(pwd)/my-untrusted.key:/tmp/wetty.key:ro \
  wettyoss/wetty \
  -p 443 \
  --force-ssh \
  --ssl-cert /tmp/wetty.cert \
  --ssl-key /tmp/wetty.key

```


### 7 - Test

Navigate to the AWS public IP of the EC2 instance: http://10.20.30.40/ssh

Supply credentials for the user whose password was just set.


_Copyright (c) 2025-2026 RX-M LLC, Cloud Native Consulting, all rights reserved_
