FROM steamcmd/steamcmd:ubuntu-22

RUN apt-get update && \
	apt-get install -y libsdl2-2.0-0:i386 git gcc g++ make curl libssl-dev libyaml-dev net-tools netcat zlib1g-dev && \
    apt-get clean

WORKDIR /home/7daystodie
ENV HOME="/home/7daystodie"
ENV PATH=$HOME/.rbenv/bin:$PATH

COPY docker/7daystodie/entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

ENTRYPOINT  ["/home/7daystodie/entrypoint.sh"]
