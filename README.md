# hermes-vk-bot
ВК бот для Hermes Agent.

draft:
1. Если Hermes Agent запущен из под WSL, то необходимо пробросить порт из локальной сети WSL в нашу (если бот запущен на том же компьютере). Для этого необходимо выполнить команду в PowerShell от имени администратора:
```
$wslIp = (wsl hostname -I).Trim().Split()[0]
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=127.0.0.1 connectport=8080 connectaddress=$wslIp
```