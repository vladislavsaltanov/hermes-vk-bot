# hermes-vk-bot
ВК бот для Hermes Agent.

draft:
1. Если Hermes Agent запущен из под WSL, то необходимо узнать локальный айпи Hermes с помощью `hostname -I`. Он начинается на `172.17....`. Его необходимо вставить в .env под ключ HERMES_URL.
