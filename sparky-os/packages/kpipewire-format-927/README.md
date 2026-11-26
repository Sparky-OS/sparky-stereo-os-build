# KPipeWire format negotiation on a repeated Throw

KPipeWire 6.7.4-1+stereo3d11 carries Zhongli Wu's upstream fix
[71ba11f](https://invent.kde.org/plasma/kpipewire/-/commit/71ba11ff887c6eb900b5541b4a8d7bf74bd3ae28).
It follows the staged +stereo3d10 closure, keeping the HEVC and constant-frame-rate patches.
The implementation grows the parameter buffer before passing the complete format list to PipeWire.
The public API is unchanged. Debian tracks the private method's new mangled symbol.
