# 使用官方的 OpenResty Alpine 镜像作为基础
FROM openresty/openresty:alpine

# 直接安装可能不是最新版，添加 官方源再安装
# RUN wget -O - https://deb.goaccess.io/gnugpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/goaccess.gpg >/dev/null  \
#    &&  echo "deb [signed-by=/usr/share/keyrings/goaccess.gpg arch=$(dpkg --print-architecture)] https://deb.goaccess.io/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/goaccess.list
#    && apt-get update   && apt-get install goaccess


# 从 Alpine 的软件源中安装 goaccess 及其所有依赖
# RUN apk update && apk add --no-cache goaccess 
RUN echo "https://mirrors.aliyun.com/alpine/v3.16/main" > /etc/apk/repositories
RUN echo "https://mirrors.aliyun.com/alpine/v3.16/community" >> /etc/apk/repositories
RUN apk add --no-cache goaccess 