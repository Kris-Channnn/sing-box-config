# sing-box_config
自用的sing-box配置

需要使用reF1nd版内核使用

singbox-manager.ps1为sing-box.exe管理脚本（cmd后台运行版本），使用cmd.exe配合 >>重定向运行，轻量化

singbox-manager_2.ps1引入了第三方工具WinSW将sing-box封装为标准的Windows服务，功能更齐全，适合服务器或多用户电脑，系统稳定性和后台管理效率更佳

[*** 二者启动后都是后台服务，可以关闭脚本，不影响服务进程，manager.ps1皆需放在与sing-box.exe同一目录下 ***]

start-manager.bat为启动脚本程序（cmd命令提示符），可放在任意位置，可编辑cd /d ""

start-manager_2.bat为启动Windows“终端”powershell版本，美化一点

server_A.json为现用配置
