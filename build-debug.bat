@rem build -TMonsterBrowser main.d -v1 -oddebug -debug -g -Xdwt -version=OLE_COM -exec %*
bud -TMonsterBrowser main.d -v1 -oddebug -debug -g -Xdwt -Xphobos -L/subsystem:console:4.0 -version=OLE_COM -exec %*
