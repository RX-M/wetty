![RX-M LLC](https://rx-m.com/rxm-cnc.svg)

# wetty setup for AWS

## What is wetty?

wetty is an open source implementation of web browsing to a Linux TTY terminal (we-tty). It listens on port 80
or 443 and accepts a Linux user login using username and password. It uses an ssh protocol over HTTP to emulate
a terminal within a browser window.

## Why not use SSH directly?

In enterprise environments, access to port 22 (ssh) is blanket denied, often by more than one block (e.g.,
zscaler, iptables, gateways, etc.) In order to access EC2 instances on AWS, we need a workaround to permit
students to access our lab machines.

## How does wetty help?

Since it is unlikely that enterprise organizations actually block access to an AWS IP - after all, many or most
web sites today are hosted on an AWS instance, so even corporate employees need browse (port 80/443) access to
AWS-hosted sites. A wetty server running on an EC2 instance forwards traffic between the ssh protocol on port 22
to an HTTP protocol on port 80/443.

Result: workaround for corporate students to gain terminal access to our AWS EC2 VMs.

## Setup on the AWS Linux box (ubuntu)

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

Edit the file /etc/ssh/sshd_config to allow password logins:

```
PasswordAuthentication yes
```

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
docker run -d --net=host --restart always wettyoss/ssh -p 80 --force-ssh

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
