.PHONY: build install audit audit-app clean

# 编译出 dist/SwitchBar.app
build:
	./scripts/build-app.sh

# 编译并安装到 /Applications，然后启动
install:
	./scripts/install.sh

# 安全自查（源码）：网络代码、外部命令、私有框架、第三方依赖
audit:
	./scripts/audit.sh

# 安全自查（编译好的程序）：联网函数、链接的框架、强化运行时、entitlements
# 也可以检查已安装的版本：./scripts/audit-binary.sh /Applications/SwitchBar.app
audit-app: build
	./scripts/audit-binary.sh

clean:
	rm -rf .build dist
