.PHONY: build install audit clean

# 编译出 dist/SwitchBar.app
build:
	./scripts/build-app.sh

# 编译并安装到 /Applications，然后启动
install:
	./scripts/install.sh

# 安全自查：网络代码、外部命令、私有框架、第三方依赖
audit:
	./scripts/audit.sh

clean:
	rm -rf .build dist
