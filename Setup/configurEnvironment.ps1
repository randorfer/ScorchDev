$installFile = "$([IO.Path]::GetTempPath())\Git-1.9.4-preview20140929.exe"
(new-object Net.WebClient).DownloadFile("https://github.com/msysgit/msysgit/releases/download/Git-1.9.4-preview20140929/Git-1.9.4-preview20140929.exe", $installFile)
& $installFile /VERYSILENT /SUPPRESSMSGBOXES