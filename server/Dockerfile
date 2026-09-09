# syntax=docker/dockerfile:1
FROM golang:1.23-bookworm AS build
WORKDIR /src
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/lxplayer-server .

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/lxplayer-server /lxplayer-server
ENV LISTEN_ADDR=:8080
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/lxplayer-server"]
