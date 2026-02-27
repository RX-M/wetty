# wetty
RX-M wetty build for lab boxes

> N.B. The host install shell script does not work. Everything installs sucessfully
> and the server runs, however when browsing to it, the browser connects, provides
> a black screen but no login prompt. The server also reports 304. I did not have
> time to take debugging any further.
>
> Both the libs installed by the shell script and those in the container image are
> several years old, Node based (yikes) and have many CVEs. If we decide to use this
> solution regularly it may be worth forking the source, updating the dependencies
> and fixing the installer or container image.

The following script can be used when standing up EC2 instances. Drop this in the 
`[advanced] --> User data` area and the script with setup wetty.

```bash
#!/bin/bash

until curl -s --head http://169.254.169.254/latest/meta-data/ >/dev/null; do
  echo "Waiting for metadata service..."
  sleep 2
done

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
