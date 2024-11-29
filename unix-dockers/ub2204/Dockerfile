FROM ubuntu:22.04
RUN apt-get update -y
RUN apt-get upgrade -y
RUN apt-get install -y curl git openssh-server
RUN apt-get install -y build-essential vim
RUN apt-get install -y net-tools curl git build-essential default-jre default-jdk
RUN apt-get install -y nginx httpie
RUN apt-get install -y iputils-ping
RUN apt-get install -y ufw
WORKDIR /home/manojmenon

EXPOSE 22
# Keep the container running indefinitely
CMD ["tail", "-f", "/dev/null"]



