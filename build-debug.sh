svnversion -n . trunk > svnversion.txt
xfbuild main.d +full +omb +Odebug +Ddebug/deps -debug -g -J. -Jflags -Jicons -Jres +xtango -version=TANGOSVN -L-lz -L-ldl -L-lgtk-x11-2.0 -L-lgnomeui-2 -L-lXtst +full

