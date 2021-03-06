FROM node:9
MAINTAINER Mahito <earthdragon77@gmail.com>
RUN apt update && apt upgrade -y

RUN mkdir /bot
ADD bin /bot/bin
ADD entrypoint.sh /bot/entrypoint.sh
ADD external-scripts.json /bot/external-scripts.json
ADD package.json /bot/package.json
ADD package-lock.json /bot/package-lock.json
ADD scripts /bot/scripts
RUN npm i npm@latest -g
RUN cd /bot && npm install

WORKDIR /bot

ENTRYPOINT "./entrypoint.sh"
