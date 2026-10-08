# The container image `act` runs workflows in.
#
# `act` needs a Docker image to execute steps. The community images it used to
# default to are no longer published for 24.04, and plain `node:24-bookworm` has
# no `docker` CLI, so the Docker chapters (30, 52) cannot smoke-test an image.
#
# This image is Node 24 plus the Docker CLI. The Docker DAEMON is the host's,
# reached through the socket `act` mounts in; no daemon runs in here.
FROM node:24-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg git jq less openssh-client \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# git is needed because act's checkout and several actions shell out to it.
RUN git config --system --add safe.directory '*' || true

CMD ["tail", "-f", "/dev/null"]