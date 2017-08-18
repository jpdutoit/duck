FROM dlanguage/dmd

ADD . .

WORKDIR /src

RUN apt-get update && \
    apt-get install -y curl ffmpeg && \
    curl -sL https://deb.nodesource.com/setup_6.x | bash && \
    apt-get install -y nodejs && \
    ./build.sh

EXPOSE 80

CMD find . && cd tools/server && node index
