call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
rc /nologo /l 0x0409 /fo resource.res resource.rc
cl /c /nologo /W3 /O2 /I include /DTXREXTRACTOR_GUI_BUILD wmn.cpp
cl /c /nologo /W3 /O2 TXRExtractor.cpp
cl /c /nologo /W3 /O2 gui.cpp
link /nologo /out:TXRExtractor_gui.exe /subsystem:windows /LIBPATH:.\lib kernel32.lib user32.lib gdi32.lib shell32.lib comdlg32.lib zlibstat.lib resource.res gui.obj wmn.obj TXRExtractor.obj

pause
exit