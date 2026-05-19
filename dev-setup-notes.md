# Настройка на локална dev среда — emart LAMP

## Проблеми и решения

---

### 1. Липсващи Composer зависимости

**Симптом:** Сайтът показва бяла страница или Fatal Error в Apache лога:
```
Drago FATAL: Липсват библиотеките от vendor/ папката.
```

**Причина:** `composer.json` дефинира `"vendor-dir": "../vendor"`, което означава че `vendor/` се инсталира в `/var/www/vendor/` (извън `public_html/`). Тази директория не е volume-mountната и изчезва при рестарт на контейнера.

**Решение:** При всеки рестарт на контейнера се изпълнява:
```bash
docker exec lamp-php84 bash -c "cd /var/www/html && composer install --no-interaction"
```

---

### 2. Сайтът връща 404 на началната страница

**Симптом:** `https://localhost/` показва "Страницата не е намерена 404".

**Причина:** Bug в `citte/sesii.php` — функцията `curPageURL()` има идентичен код в двата клона на `if/else`, и двата добавят порта към URL-а (`:80` или `:443`). Резултатът `localhost:443/` не съвпадал с `$zaskiba1 = "localhost/"` и рутерът не разпознавал началната страница.

**Решение:** Поправена `curPageURL()` в `citte/sesii.php`:
```php
function curPageURL()
{
    $pageURL = '';
    $port = $_SERVER["SERVER_PORT"];
    if ($port != "80" && $port != "443") $pageURL .= $_SERVER["SERVER_NAME"] . ":" . $port . $_SERVER["REQUEST_URI"];
    else $pageURL .= $_SERVER["SERVER_NAME"] . $_SERVER["REQUEST_URI"];
    return $pageURL;
}
```

---

### 3. Преминаване към HTTPS (за Secure cookies)

**Симптом:** Добавянето в количката не работи — попъпът не се показва, нищо не се добавя.

**Причина:** Всички `setcookie()` извиквания имат `Secure=true` — бисквитките се изпращат само по HTTPS. При HTTP браузърът ги игнорира.

**Решение:** Настройване на HTTPS локално с mkcert.

#### Стъпки:

**a) Инсталиране на mkcert:**
```bash
sudo apt-get install -y mkcert libnss3-tools
```

**b) Генериране на сертификат:**
```bash
sudo chmod 777 /path/to/emart-lamp/config/ssl/
cd /path/to/emart-lamp/config/ssl/
mkcert localhost
mv localhost.pem cert.pem
mv localhost-key.pem cert-key.pem
```

**c) Активиране на HTTPS vhost** в `config/vhosts/default.conf`:
```apache
<VirtualHost *:443>
    ServerAdmin webmaster@localhost
    DocumentRoot ${APACHE_DOCUMENT_ROOT}
    ServerName localhost
    <Directory ${APACHE_DOCUMENT_ROOT}>
        AllowOverride all
    </Directory>
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/cert.pem
    SSLCertificateKeyFile /etc/apache2/ssl/cert-key.pem
</VirtualHost>
```

**d) Добавяне на CA в Windows** (за WSL2 — браузърът е на Windows):

В PowerShell като администратор:
```powershell
Import-Certificate -FilePath "\\wsl.localhost\Ubuntu\home\<user>\.local\share\mkcert\rootCA.pem" -CertStoreLocation Cert:\LocalMachine\Root
```
След това рестартирай браузъра.

**e) Обновяване на `citte/zaskiba.php`** — смяна на URL-овете към `https://localhost/`:
```php
$canonical = "https://localhost";
$zaskiba1 = "localhost/";
$zaskiba2 = "localhost/";
$zaskuban = "localhost";
$patisht = "https://localhost/";
$patsnim = "https://localhost/";
$patstyl = "https://localhost/";
$patscrp = "https://localhost/";
```

---

### 4. Fatal Error — липсваща `tmp/` директория

**Симптом:** Продуктовата страница се прекъсва наполовина, `transinform` div липсва от HTML, JS грешка:
```
Uncaught TypeError: Cannot set properties of null (setting 'innerHTML') at vkolichkata
```

**Причина:** `stokipodrobno.php` опитва да прочете `/var/www/html/tmp/filtri`, но директорията `tmp/` не съществува. PHP 8 хвърля `TypeError: count(): Argument #1 must be of type Countable|array, false given`.

**Решение:**
```bash
mkdir -p public_html/tmp
touch public_html/tmp/filtri
```

---

### 5. Permission denied за custom error log

**Симптом:**
```
Warning: error_log(...custom_logs/custom_error.log): Failed to open stream: Permission denied
```

**Причина:** `custom_logs/` е собственост на хост потребителя. Apache в контейнера върви като `www-data` и няма write права.

**Решение:**
```bash
chmod 777 public_html/custom_logs/
chmod 666 public_html/custom_logs/custom_error.log
```

---

## Команди при всеки рестарт на контейнера

```bash
docker compose up -d
docker exec lamp-php84 bash -c "cd /var/www/html && composer install --no-interaction"
```
