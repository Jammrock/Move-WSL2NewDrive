# Move-WSL2NewDrive
Simple menu driven system to move a WSL2 backing VHDX file to a new directory.

Tested on Windows 11 with PowerShell 7.2.2, using Windows Terminal. It should work on Windows 10 and Windows PowerShell 5.1, but it is considered untested until someone tells me it works.

The script is an automated version of work originally done by sonook.

https://github.com/MicrosoftDocs/WSL/issues/412#issuecomment-828924500


## WARNING

This is tested using only a single VHDX mounted to the distro, and with only a single VHDX in distro's base path (where Windows puts the initial virtual hard drive file (VHDX)). Please use extreme caution if you are using a custom setup with multiple VHDX files mounted to your distro.


# Legal Stuff

The usual OSS stuff applies. Use at your own risk. No warranty or guarantees. I'm not responsible if something breaks or data is lost.

If your distro files are critical, please backup the distro using "wsl --export" first.
