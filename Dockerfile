FROM dlanguage/dmd

ADD . .

WORKDIR /src

RUN apt-get update && \
    apt-get install -y curl ffmpeg git && \
    curl -sL https://deb.nodesource.com/setup_6.x | bash && \
    apt-get install -y nodejs && \
    ./build.sh && \
    cd tools/server/site && npm install && npm run build && rm -rf node_modules

EXPOSE 80

CMD find . && cd tools/server && node index
