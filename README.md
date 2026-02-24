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
