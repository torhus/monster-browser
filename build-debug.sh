hg id -i > revision.txt
xfbuild main.d -Isrc +full +omb +Odebug +Ddebug/deps -debug -g -J. -Jflags -Jicons -Jres +xtango -version=TANGOSVN -L-lz -L-ldl -L-lgtk-x11-2.0 -L-lgnomeui-2 -L-lXtst

