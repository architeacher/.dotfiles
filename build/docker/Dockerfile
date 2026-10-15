# Throwaway image to test a key restore on a "fresh machine".
# bash:3.2 is the same Bash version as macOS. No keys are baked in.
FROM    bash:3.2

RUN     apk add --no-cache \
            age \
            gnupg \
            pinentry \
            openssh-keygen \
            ripgrep \
            tar

WORKDIR /root
