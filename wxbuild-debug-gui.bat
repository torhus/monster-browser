rem bud -TMonsterBrowser main.d -v1 -gui -debug -g -Xdwt -Xphobos -oddebug-gui -version=NO_STDOUT -version=OLE_COM -exec %*
bud -TMonsterBrowser main.d -gui -debug -g -Xwx -Xphobos -oddebug-gui -version=NO_STDOUT wxd.lib wxc.lib -LIBPATH=c:\prog\wxWidgets-2.6.4\lib\dmc_lib wxbase26d.lib wxmsw26d_core.lib wxmsw26d_adv.lib wxmsw26d_html.lib wxbase26d_xml.lib wxmsw26d_xrc.lib wxexpatd.lib wxjpegd.lib wxpngd.lib wxtiffd.lib kernel32.lib user32.lib gdi32.lib comdlg32.lib winspool.lib winmm.lib shell32.lib comctl32.lib ole32.lib oleaut32.lib uuid.lib rpcrt4.lib advapi32.lib wsock32.lib odbc32.lib %*
