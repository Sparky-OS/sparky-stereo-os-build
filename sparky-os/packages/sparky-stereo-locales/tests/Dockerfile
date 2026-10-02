FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
COPY sparky-repo.asc /etc/apt/trusted.gpg.d/sparky-repo.asc
COPY sparky.sources /etc/apt/sources.list.d/sparky.sources
RUN apt-get update && apt-get -y install --no-install-recommends ca-certificates \
 libreoffice-writer firefox-esr hunspell-tools yad \
 firefox-esr-l10n-pl firefox-esr-l10n-pt-br firefox-esr-l10n-pt-pt firefox-esr-l10n-de firefox-esr-l10n-ja firefox-esr-l10n-zh-cn firefox-esr-l10n-zh-tw firefox-esr-l10n-en-gb \
 libreoffice-l10n-pl libreoffice-l10n-pt-br libreoffice-l10n-pt libreoffice-l10n-de libreoffice-l10n-ja libreoffice-l10n-zh-cn libreoffice-l10n-zh-tw libreoffice-l10n-en-gb \
 libreoffice-help-pl libreoffice-help-pt-br libreoffice-help-pt libreoffice-help-de libreoffice-help-en-us libreoffice-help-ja libreoffice-help-zh-cn libreoffice-help-zh-tw \
 hunspell-pl hunspell-pt-br hunspell-pt-pt hunspell-de-de hunspell-de-at hunspell-en-us hunspell-en-gb hunspell-fr hunspell-sr hunspell-hr \
 hyphen-pl hyphen-pt-br hyphen-pt-pt hyphen-de hyphen-en-us hyphen-fr \
 mythes-pl mythes-pt-br mythes-pt-pt mythes-de mythes-en-us mythes-fr \
 fcitx5 fcitx5-mozc fcitx5-chinese-addons fcitx5-chewing fcitx5-hangul fcitx5-unikey \
 && apt-get update && apt-get -y install sparky-remsu || true
