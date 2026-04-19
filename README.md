# hermes-vk-bot
ВК бот для Hermes Agent.

draft:
1. Если Hermes Agent запущен из под WSL, то необходимо пробросить порт из локальной сети WSL в нашу (если бот запущен на том же компьютере). Для этого необходимо выполнить команду в PowerShell от имени администратора:
```
$wslIp = (wsl hostname -I).Trim().Split()[0]
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=127.0.0.1 connectport=8080 connectaddress=$wslIp
```

2. В .env необходимо добавить ALLOWED_USERS и подставить туда через запятую айди пользователей, которые допускаются к использованию бота. Пример:
```
ALLOWED_USERS=333222111
```

3. В .env необходимо добавить VK_GROUP_ID сообщества, в котором будет бот, а также VK_TOKEN этого сообщества. Версия vk_longpool - 5.131.

Запуск: 
```
bundle exec ruby bin/bot
```