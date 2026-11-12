
# Автоматический деплой API

Workflow `REST API` проверяет сервер, движок и миграции при изменениях серверных
файлов. ВМ `almostready-api` раз в 10 минут читает GitHub Actions API и берёт
точный SHA последнего успешного запуска на `push` в `main`. Workflow `Deploy API`
подтверждает этот SHA по публичному HTTPS и проверяет состояние мониторинга.

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

## Обновление скрипта на ВМ

Скрипт, который запускает таймер, обновляется отдельно. После merge скачайте
проверенный коммит на ВМ. В каталоге этой копии выполните:

```bash
sudo systemctl stop almostready-deploy.timer
while [[ $(systemctl show -p ActiveState --value almostready-deploy.service) =~ ^(activating|active|deactivating)$ ]]; do
  sleep 2
done
install -m 600 deploy/deploy.py ~/almostready-deploy/bin/.deploy.py.new
mv ~/almostready-deploy/bin/.deploy.py.new ~/almostready-deploy/bin/deploy.py
sudo systemctl start almostready-deploy.timer

```

Состояние релиза и существующие тома остаются на месте. Таймер подхватывает
готовый релиз и запускает мониторинг, даже если версия API уже развёрнута.

## Мониторинг

После готовности API скрипт обновляет Compose-проект `almostdone-monitoring`.
На каждом проходе скрипт проверяет Grafana, Prometheus и свежий успешный
сбор метрик API. Если версия и конфигурация не менялись, контейнеры не перезапускаются.
При сбое мониторинга API продолжает работать. Таймер повторяет попытку,
а `Deploy API` показывает отдельно, что API уже готов.

Prometheus и Grafana доступны на ВМ через `127.0.0.1` и сохраняют данные
в томах Compose. Публичный `/metrics` возвращает HTTP 404. Для просмотра
используйте SSH-туннель с рабочего компьютера:

```bash
ssh -i ~/.ssh/almostready_yc -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 deploy@51.250.76.77

```

Grafana открывается по `http://localhost:3000`, Prometheus по `http://localhost:9090`.
Для новой Grafana пользователь `admin`. При первом запуске скрипт сохраняет
сгенерированный пароль в `~/almostready-deploy/monitoring.env` с правами `0600`.
Если в `~/almostready/server/.env` задан `GRAFANA_ADMIN_PASSWORD`, он имеет
приоритет при инициализации. Существующая Grafana сохраняет свои учётные записи.

## Обновление PostgreSQL

Для существующей базы добавляйте новые совместимые SQL-миграции в `db/migrations/`.
`db/schema.sql` и `db/seed.sql` инициализируют пустую базу. Изменение схемы или
каталога для пользователей должно быть в новой миграции. CI сверяет SQL ранее
влитых миграций с развёрнутой версией для `001` и `002` и с первым merge для
последующих миграций. Перед миграциями скрипт
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
