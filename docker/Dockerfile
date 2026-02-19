FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ============================================================
# 1. System packages
# ============================================================
RUN apt-get update && apt-get install -y \
    curl wget git jq htop nano vim \
    build-essential ca-certificates gnupg lsb-release \
    inotify-tools openssh-server locales rsync \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# ============================================================
# 2. Node.js 20 LTS
# ============================================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 3. Python 3.12
# ============================================================
RUN apt-get update && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y python3.12 python3.12-venv python3.12-dev python3-pip \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 4. code-server (pre-install for faster startup)
# ============================================================
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/opt/code-server

# ============================================================
# 5. SSH server setup
# ============================================================
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo "AllowUsers coder" >> /etc/ssh/sshd_config

# ============================================================
# 6. Create coder user (limited sudo — apt/dpkg only)
# ============================================================
RUN apt-get update && apt-get install -y sudo && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash -u 1000 coder \
    && mkdir -p /etc/sudoers.d \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg" > /etc/sudoers.d/coder \
    && chmod 440 /etc/sudoers.d/coder

# ============================================================
# 7. Bash history tracking (invisible to candidate)
# ============================================================
RUN cat >> /etc/bash.bashrc << 'BASHRC'

# --- system telemetry (do not modify) ---
export HISTFILE=/var/log/sandbox/.bash_history_audit
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTCONTROL=
export PROMPT_COMMAND='history -a'
shopt -s histappend 2>/dev/null
# --- end system telemetry ---
BASHRC

# ============================================================
# 8. Tracking & startup scripts
# ============================================================
RUN mkdir -p /usr/lib/sandbox
COPY agent-helper.sh /usr/lib/sandbox/agent-helper
COPY startup.sh /usr/lib/sandbox/startup.sh
COPY entrypoint.sh /usr/lib/sandbox/entrypoint.sh
RUN chmod +x /usr/lib/sandbox/*

# ============================================================
# 9. Working directories
# ============================================================
RUN mkdir -p /home/coder/workspace /var/log/sandbox \
    && chown -R coder:coder /home/coder \
    && chown root:root /var/log/sandbox \
    && chmod 700 /var/log/sandbox

EXPOSE 22 13337

ENTRYPOINT ["/usr/lib/sandbox/entrypoint.sh"]
