
# Автоматический деплой API

Workflow `REST API` проверяет сервер, движок и миграции при изменениях серверных
файлов. ВМ `almostready-api` раз в 10 минут читает GitHub Actions API и берёт
точный SHA последнего успешного запуска на `push` в `main`. Workflow `Deploy API`
подтверждает этот SHA в ответе работающего API по публичному HTTPS.

## Установка на существующей ВМ

Команды выполняются на ВМ от пользователя `deploy`. Нужны Git, Python 3.12,
Docker Compose и работающий стек из `~/almostready`. Файл `server/.env`, том
`almostdone_pgdata` и тома Caddy используются из текущего развёртывания.
Файл `~/almostready/.revision` должен содержать SHA работающего образа API.

```bash
setup=$(mktemp -d)
git clone --branch main --single-branch https://github.com/a-nechaeva/AlmostDone.git "$setup"
install -d -m 700 ~/almostready-deploy/bin
install -m 600 "$setup"/deploy/{deploy.py,compose.yml,Caddyfile} ~/almostready-deploy/bin/
python3 ~/almostready-deploy/bin/deploy.py --bootstrap
sudo install -m 644 "$setup"/deploy/almostready-deploy.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now almostready-deploy.timer

```

Bootstrap сохраняет образ уже работающего API и добавляет в Caddy статус деплоя.
Если установка прервалась, повторите `--bootstrap` для восстановления Caddy.
После установки перезапустите последний послемёржевый `REST API` на `main`, чтобы
`Deploy API` проверил развёртывание. Скрипт таймера устанавливается отдельно на ВМ.
`compose.yml` и `Caddyfile` берутся из каждого проверенного коммита.

```bash
systemctl list-timers almostready-deploy.timer
sudo journalctl -u almostready-deploy.service -n 100
curl -fsS https://51.250.76.77/_deploy/status.json
curl -fsS https://51.250.76.77/api/v1/health/ready

```

## Обновление PostgreSQL

Для существующей базы добавляйте новые совместимые SQL-миграции в `db/migrations/`.
`db/schema.sql` и `db/seed.sql` инициализируют пустую базу. Изменение схемы или
каталога для пользователей должно быть в новой миграции. Перед миграциями скрипт
проверяет дамп PostgreSQL и сохраняет его в `~/almostready-deploy/backups/`.

Новый образ собирается до переключения API. Если проверка после переключения
на ВМ падает, скрипт возвращает предыдущий образ и конфигурацию. Поэтому миграции
для автодеплоя должны поддерживать предыдущую версию API. После исправления причины
сбоя перезапустите соответствующий `REST API` workflow на `main`. Откат данных и
смену версии PostgreSQL проводят отдельно.

Если проверка из GitHub Actions обнаружила проблему с публичным HTTPS после
локально успешного переключения, можно вернуть предыдущий образ. Остановите
таймер и дождитесь завершения текущего `almostready-deploy.service`.

```bash
sudo systemctl stop almostready-deploy.timer
python3 ~/almostready-deploy/bin/deploy.py --rollback
sudo systemctl start almostready-deploy.timer

```
