# syntax=docker/dockerfile:1
FROM golang:1.23-bookworm AS build

# 构建期要从模块代理拉依赖。默认走国内镜像（goproxy.cn）——本服务的部署环境在国内，
# 直连 proxy.golang.org 会超时；海外环境可用下面这行覆盖：
#   docker build --build-arg GOPROXY=https://proxy.golang.org,direct .
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}

WORKDIR /src
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/lxplayer-server .

# 运行镜像：原来用的 gcr.io/distroless 在部分网络环境（含本部署服务器）不可达，
# 换成 Docker Hub 上的 alpine——同样很小，且纯 Go 静态二进制在 musl 上可直接运行。
# 以 nobody(65534) 运行；数据库卷需在宿主机 chown 65534:65534 才可写。
FROM alpine:3.20
COPY --from=build /out/lxplayer-server /lxplayer-server
ENV LISTEN_ADDR=:10044
EXPOSE 10044
USER 65534:65534
ENTRYPOINT ["/lxplayer-server"]
