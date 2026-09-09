FROM aishell:foundation

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# >>> emacs >>>
# emacs/README.md wants Emacs 30.1 or newer and transient 0.7.2; trixie's
# emacs-nox is 30.1 and bundles transient 0.7.2.2, so neither is built here.
# evil and goto-chg let legu-tests.el run its evil group instead of skipping it.
# evil-collection is not packaged for trixie, and no test's skip guard asks for
# it -- the group gates on evil alone -- so it stays out.
ARG EMACS_VERSION=1:30.1+1-6+deb13u1
ARG EVIL_VERSION=1.14.2-4
ARG GOTO_CHG_VERSION=1.7.5-3
RUN apt-get update; \
    apt-get install -y --no-install-recommends \
    "emacs-nox=${EMACS_VERSION}" \
    "elpa-evil=${EVIL_VERSION}" \
    "elpa-goto-chg=${GOTO_CHG_VERSION}"; \
    rm -rf /var/lib/apt/lists/*; \
    emacs --version
# emacs -Q, which the suite needs, drops the site files that put these on
# `load-path`, so the evil group is run with -L /usr/share/emacs/site-lisp/elpa/evil-1.14.2
# and -L /usr/share/emacs/site-lisp/elpa/goto-chg-1.7.5.
# <<< emacs <<<

# >>> shells >>>
# test/cli_test.clj drives the completion snippets through all three, and since
# d910ab8 a missing shell fails the suite rather than skipping it.
ARG ZSH_VERSION=5.9-8+b23
ARG FISH_VERSION=4.0.2-1
RUN apt-get update; \
    apt-get install -y --no-install-recommends \
    "zsh=${ZSH_VERSION}" "fish=${FISH_VERSION}"; \
    rm -rf /var/lib/apt/lists/*; \
    zsh --version; \
    fish --version
# <<< shells <<<

# >>> clojure (managed) >>>
# JDK 25 from Eclipse Temurin (foundation only ships JRE 17 headless).
COPY --from=eclipse-temurin:25-jdk-jammy /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk \
    PATH="/opt/java/openjdk/bin:${PATH}"

ARG CLOJURE_VERSION=1.12.6.1673
RUN curl -fsSL "https://github.com/clojure/brew-install/releases/download/${CLOJURE_VERSION}/linux-install.sh" -o /tmp/linux-install.sh; \
    bash /tmp/linux-install.sh; \
    rm /tmp/linux-install.sh; \
    clojure --version

ARG CLOJURE_LSP_VERSION=2026.07.06-14.34.19
RUN curl -fsSL "https://github.com/clojure-lsp/clojure-lsp/releases/download/${CLOJURE_LSP_VERSION}/clojure-lsp-native-static-linux-amd64.zip" -o /tmp/clojure-lsp.zip; \
    unzip /tmp/clojure-lsp.zip -d /usr/local/bin; \
    rm /tmp/clojure-lsp.zip; \
    clojure-lsp --version

ARG CLJ_KONDO_VERSION=2026.08.04
RUN curl -fsSL "https://github.com/clj-kondo/clj-kondo/releases/download/v${CLJ_KONDO_VERSION}/clj-kondo-${CLJ_KONDO_VERSION}-linux-static-amd64.zip" -o /tmp/clj-kondo.zip; \
    unzip /tmp/clj-kondo.zip -d /usr/local/bin; \
    rm /tmp/clj-kondo.zip; \
    clj-kondo --version

# Clojure MCP
ARG CLOJURE_MCP_VERSION=v0.5.1
ARG CLOJURE_MCP_SHA=c9cdd6bf61b2265954f0445f8bea389c50b09bcb
RUN clojure -Ttools install io.github.bhauman/clojure-mcp "{:git/tag \"${CLOJURE_MCP_VERSION}\" :git/sha \"${CLOJURE_MCP_SHA}\"}" :as mcp

ARG CLOJURE_MCP_LIGHT_VERSION=0.2.2
RUN bbin install https://github.com/bhauman/clojure-mcp-light.git --tag "v${CLOJURE_MCP_LIGHT_VERSION}"; \
    bbin install https://github.com/bhauman/clojure-mcp-light.git --tag "v${CLOJURE_MCP_LIGHT_VERSION}" --as clj-nrepl-eval --main-opts '["-m" "clojure-mcp-light.nrepl-eval"]'; \
    bbin install https://github.com/bhauman/clojure-mcp-light.git --tag "v${CLOJURE_MCP_LIGHT_VERSION}" --as clj-paren-repair --main-opts '["-m" "clojure-mcp-light.paren-repair"]'

ARG CLJ_SURGEON_SHA=8325ff425410569ddc7ecd2fd01afaf8f6a8b140
RUN bbin install https://github.com/realgenekim/clj-surgeon.git --git/sha "${CLJ_SURGEON_SHA}"; \
    curl -fsSL "https://raw.githubusercontent.com/realgenekim/clj-surgeon/${CLJ_SURGEON_SHA}/resources/clj-kondo-admission.py" -o /usr/local/bin/clj-kondo-admission; \
    chmod +x /usr/local/bin/clj-kondo-admission; \
    clj-surgeon --version
# :ls, :declares, and :fix-declares run clj-kondo through this gate and refuse without it.
ENV CLJ_SURGEON_CLJ_KONDO_ADMISSION=/usr/local/bin/clj-kondo-admission
# <<< clojure (managed) <<<

# >>> knot (managed) >>>
ARG KNOT_VERSION=0.12.0
RUN bbin install https://github.com/UniSoma/knot.git --tag "v${KNOT_VERSION}"
# <<< knot (managed) <<<

