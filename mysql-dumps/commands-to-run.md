# MySQL Import Commands

Изпълни командите **от директорията на проекта** (`/home/pydiii/emart`).

---

## 1. Пресъздай базите (imartap и inmarta бяха изтрити)

```bash
docker exec lamp-mysql8 mysql -uroot -ptiger -e "
DROP DATABASE IF EXISTS iimarta;
DROP DATABASE IF EXISTS imartap;
DROP DATABASE IF EXISTS inmarta;
CREATE DATABASE iimarta CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE imartap CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE inmarta CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
"
```

---

## 2. Импортирай дъмповете (поред, изчакай всяка да завърши)

```bash
docker exec -i lamp-mysql8 mysql -uroot -ptiger iimarta < mysql-dumps/iimarta.sql
```

```bash
docker exec -i lamp-mysql8 mysql -uroot -ptiger imartap < mysql-dumps/imartap.sql
```

```bash
docker exec -i lamp-mysql8 mysql -uroot -ptiger inmarta < mysql-dumps/inmarta.sql
```

---

## 3. Провери дали импортът още върви (активни процеси в контейнера)

```bash
docker exec lamp-mysql8 mysql -uroot -ptiger -e "SHOW PROCESSLIST;"
```

Докато импортира ще виждаш редове с `Query` и нещо като `INSERT INTO ...` или `ALTER TABLE ...`.
Когато всичко приключи ще остане само един ред `Sleep` или изобщо нищо.

---

## 4. Провери колко таблици са заредени до момента

```bash
docker exec lamp-mysql8 mysql -uroot -ptiger -e "
SELECT table_schema AS 'База', COUNT(*) AS 'Таблици'
FROM information_schema.tables
WHERE table_schema IN ('iimarta','imartap','inmarta')
GROUP BY table_schema;"
```

**Очакван резултат:**

| База    | Таблици |
|---------|---------|
| iimarta | 33      |
| imartap | 26      |
| inmarta | 131     |
