@rem build -TMonsterBrowser main.d -v1 -gui -debug -g -Xdwt -oddebug-gui -version=NO_STDOUT -version=OLE_COM -exec %*
bud -TMonsterBrowser main.d -v1 -gui -debug -g -Xdwt -Xphobos -oddebug-gui -version=NO_STDOUT -version=OLE_COM -exec %*
@rem rebuild -ofMonsterBrowser main.d -v1 -gui -debug -g -Xdwt -oddebug-gui -version=NO_STDOUT -version=OLE_COM
