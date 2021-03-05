PGG := $(GOPATH)/bin/protoc-gen-go
PGGG := $(GOPATH)/bin/protoc-gen-grpc-gateway
FFJ := $(GOPATH)/bin/ffjson
PKGS    := $(shell go list ./... | grep -v rpc)

VERSION := $(shell git describe --tags 2> /dev/null || echo "unreleased")
V_DIRTY := $(shell git describe --exact-match HEAD 2> /dev/null > /dev/null || echo "-unreleased")
GIT     := $(shell git rev-parse --short HEAD)
DIRTY   := $(shell git diff-index --quiet HEAD 2> /dev/null > /dev/null || echo "-dirty")

GOFILES := $(shell find . -type f | grep go$$ ) rpc/qproxy.pb_ffjson.go

default: build/qproxy.linux

build/qproxy.linux: ${GOFILES}
	@echo "$@"
	@GOOS=linux GOARCH=$(TARGETARCH) CGO_ENABLED=0 go build -o build/qproxy.linux -ldflags\
		"-X github.com/wish/qproxy.Version=$(VERSION)$(V_DIRTY) \
		 -X github.com/wish/qproxy.Git=$(GIT)$(DIRTY)" \
		github.com/wish/qproxy/cmd/qproxy

build/qproxy.darwin: ${GOFILES}
	@echo "$@"
	@GOOS=darwin CGO_ENABLED=0 go build -o build/qproxy.darwin -ldflags\
		"-X github.com/wish/qproxy.Version=$(VERSION)$(V_DIRTY) \
		 -X github.com/wish/qproxy.Git=$(GIT)$(DIRTY)" \
		github.com/wish/qproxy/cmd/qproxy

# all .go files are deps, so these are fine specified as such:
rpc/qproxy.pb.go: rpc/qproxy.proto ${PGG}
	@echo "protoc $@"
	@protoc \
	        -I /usr/local/include -I.\
	        -I third_party/googleapis \
		-I rpc/ rpc/qproxy.proto \
		--go_out=.
	@sed s/,omitempty// $@ > $@.tmp
	@mv $@.tmp $@
	@${PGIT} -input=$@ 2> /dev/null

# all .go files are deps, so these are fine specified as such:
rpc/qproxy_grpc.pb.go: rpc/qproxy.proto ${PGG}
	@echo "protoc $@"
	@protoc \
	        -I /usr/local/include -I.\
	        -I third_party/googleapis \
		-I rpc/ rpc/qproxy.proto \
		--go-grpc_opt=require_unimplemented_servers=false \
		--go-grpc_out=.

rpc/qproxy.pb.gw.go: rpc/qproxy.proto ${PGGG}
	@echo "protoc $@"
	@protoc -I /usr/local/include -I. \
		-I third_party/googleapis \
		--grpc-gateway_opt paths=source_relative \
        --grpc-gateway_opt generate_unbound_methods=true \
		--grpc-gateway_out=logtostderr=true:. rpc/qproxy.proto

rpc/qproxy.pb_ffjson.go: rpc/qproxy.pb.go rpc/qproxy.pb.gw.go rpc/qproxy_grpc.pb.go ${FFJ}
	@rm -f rpc/qproxy.pb_jsonpb.go
	ffjson rpc/qproxy.pb.go

.PHONY: coverage
coverage:
	@go test -coverprofile=/tmp/cover github.com/wish/qproxy
	@go tool cover -html=/tmp/cover -o coverage.html
	@rm /tmp/cover

# the reason we introduce test and vtest is to have a way to view the results
# of failing tests, but being silient in the successful case (silence is golden
# principle)
.PHONY: test
test: default
	@echo "running unittests"
	@go test -cover ${PKGS} > /dev/null

.PHONY: vtest
vtest: default
	@go test -cover -v ${PKGS}

.PHONY: clean
clean:
	rm -rf build
	rm -f rpc/qproxy.pb.go rpc/qproxy.pb.gw.go rpc/qproxy.pb_ffjson.go rpc/qproxy.pb_jsonpb.go
	rm -f bin/ffjson bin/protoc-gen-go bin/protoc-gen-grpc-gateway bin/protoc-go-inject-tag

.PHONY: release
release: default test build/checksums.256

build/checksums.256: build/qproxy.linux build/qproxy.darwin
	@rm -f build/checksums.256
	@cd build && shasum -a 256 * > checksums.256

$(PGG):
	@go get -u github.com/golang/protobuf/protoc-gen-go
	@go get -u google.golang.org/grpc/cmd/protoc-gen-go-grpc

$(FFJ):
	@go get -u github.com/pquerna/ffjson

$(PGGG):
	@go get -u github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway
	@go get -u github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2

