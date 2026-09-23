# emart-lamp

LAMP стек в Docker. Кодът на магазина е в `public_html/` (отделно git repo), Drizzle
схемите и документацията по issue-тата — в `emart-monorepo/` (също отделно repo).
Миграциите и seed-овете са в `database/`.

## Зависимостите се инсталират от контейнера, но живеят на хоста

`vendor/` (в root-а на репото) и `public_html/node_modules/` са bind mount-нати,
не named volumes. Инсталира ги контейнерът, но файловете са на хоста — IDE-то ги
вижда и `git`/`grep` ги стигат. И двете са в `.gitignore`.

```bash
docker exec -u 1000:1000 -w /var/www/html -e COMPOSER_HOME=/tmp/composer \
  lamp-php84 composer install --no-interaction
```

`-u 1000:1000` е задължителен — `lamp-php84` върви като root и без него vendor
файловете излизат root-owned на хоста. По същата причина `COMPOSER_HOME` сочи
`/tmp`: домашната директория на root не е писаема за uid 1000. `node` контейнерът
вече има `user: "1000:1000"` в `docker-compose.yml`, така че `npm install` в
неговия `command:` пише правилно без допълнителни флагове.

`vendor/` трябва да съществува на хоста **преди** `docker compose up` — иначе
докер я създава като root. Ако е изчезнала: `mkdir -p vendor` и после `up`.

## Тестовете се пускат в контейнера, не на хоста

```bash
docker exec -w /var/www/html -e XDEBUG_MODE=off lamp-php84 composer test
```

`composer test` = PHPUnit (`citte/tests/phpunit/`) + assert скриптовете
(`citte/tests/run-asserts.sh`, всеки в собствен php процес).

Хостът има свой PHP (herd-lite 8.4.1) и след bind mount-а вижда
`vendor/bin/phpunit`, но контейнерът е канонична среда: PHP 8.4.24 с
`mysqli`, `intl`, `gd`, `imagick`, `redis` — тоест същото, което изпълнява сайта.

Шум в изхода, който не е провал:

- `fatal: detected dubious ownership in repository at '/var/www/html'` — git вътре
  в контейнера вижда чужд собственик на mount-а.
- `Xdebug: [Step Debug] Time-out connecting to debugging client` — излиза само ако
  изпуснеш `XDEBUG_MODE=off`; няма слушащ дебъгер на `host.docker.internal:9003`.

Отделни assert скриптове се пускат така:

```bash
docker exec lamp-php84 php -d zend.assertions=1 \
  /var/www/html/citte/tests/lib/PromoCalcTest.php
```

Повече в `public_html/citte/docs/running-tests.md`.

## Контейнери

| Контейнер | Какво |
|---|---|
| `lamp-php84` | Apache + PHP 8.4 (root); `public_html/` → `/var/www/html`, `vendor/` → `/var/www/vendor` |
| `lamp-mysql8` | MySQL 8 |
| `lamp-redis` | Redis |
| `lamp-phpmyadmin` | phpMyAdmin |
| `lamp-node` | Node 22 като uid 1000; `public_html/` → `/app`, tailwind watch на `globals.css` |

Имената идват от `COMPOSE_PROJECT_NAME` и `PHPVERSION` в `.env`. Сайтът се отваря
на `https://localhost:8453/` (`HOST_MACHINE_SECURE_HOST_PORT`).
