FROM mcr.microsoft.com/devcontainers/base:bookworm

# Lua 5.1 is what the WoW client embeds, so the toolchain targets 5.1 explicitly.
RUN apt-get update && apt-get install -y --no-install-recommends \
    lua5.1 \
    liblua5.1-0-dev \
    luarocks \
    build-essential \
    zip \
    rsync \
    unzip \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Linter (luacheck) + a 5.1 interpreter on PATH as `lua`
RUN luarocks --lua-version=5.1 install luacheck \
    && ln -sf /usr/bin/lua5.1 /usr/local/bin/lua

# StyLua formatter (static binary release)
ARG STYLUA_VERSION=2.5.2
RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
         amd64) SL_ARCH=x86_64 ;; \
         arm64) SL_ARCH=aarch64 ;; \
         *) echo "unsupported arch $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/stylua.zip \
        "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-${SL_ARCH}.zip" \
    && unzip -q /tmp/stylua.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/stylua \
    && rm /tmp/stylua.zip

WORKDIR /workspace
