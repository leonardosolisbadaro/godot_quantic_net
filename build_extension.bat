@echo off
echo ==================================================
echo COMPILANDO GDExtension do QuanticNet...
echo ==================================================

set "PYTHON_PATH=C:\Users\LEONARDO\AppData\Local\Programs\Python\Python311\python.exe"
set "SCONS_PATH=C:\Users\LEONARDO\AppData\Local\Programs\Python\Python311\Scripts\scons.exe"

REM Verifica se scons está instalado, senão tenta instalar via pip
if not exist "%SCONS_PATH%" (
    echo Instalando scons...
    "%PYTHON_PATH%" -m pip install scons
)

echo Executando scons...
"%PYTHON_PATH%" "%SCONS_PATH%" target=template_debug

if %ERRORLEVEL% equ 0 (
    echo.
    echo ==================================================
    echo SUCESSO! A extensao C++ do QuanticNet foi compilada!
    echo ==================================================
) else (
    echo.
    echo ==================================================
    echo ERRO na compilacao! Verifique os logs acima.
    echo ==================================================
)
pause

