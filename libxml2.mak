!IFNDEF VS
!ERROR VS missing
!ENDIF

!IFNDEF ARCH
!ERROR ARCH missing
!ENDIF

all:
	cd ..\libxml2\win32
	cscript configure.js lib=$(MAKEDIR)\..\deps\lib include=$(MAKEDIR)\..\deps\include debug=yes mem_debug=yes vcmanifest=yes prefix=$(MAKEDIR)\build
	nmake /f Makefile.msvc
	nmake /f Makefile.msvc install

	nmake /f Makefile.msvc clean
	cscript configure.js lib=$(MAKEDIR)\..\deps\lib include=$(MAKEDIR)\..\deps\include vcmanifest=yes prefix=$(MAKEDIR)\build
	nmake /f Makefile.msvc
	nmake /f Makefile.msvc install

	cd $(MAKEDIR)
	del /q build\bin\run*
	del /q build\bin\test*
	del /q build\bin\xml*.pdb
