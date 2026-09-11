# Instrucciones — Zabbix en Docker

Guía operativa: copiar el proyecto, instalar, entrar, backups, apagar el server y limpiar si algo falla.

El README del repo (portafolio) está en [README.md](README.md).

## Qué es este proyecto

Zabbix 7.0 LTS en contenedores, con PostgreSQL. En Debian se usan **dos pasos**:

1. `prepare.sh` — instala Docker Engine y Compose (**una sola vez**). Solo Debian **11, 12 y 13**.
2. `install.sh` — descarga imágenes y levanta Zabbix. Sirve en cualquier host que ya tenga Docker Compose.

Debian 13.6 es el objetivo original; 12 y 11 usan el mismo repo oficial de Docker. No uses Debian 10 ni Ubuntu con `prepare.sh`.

---

## Compatibilidad

| Qué | Dónde corre |
| --- | --- |
| `prepare.sh` | Debian 11 (bullseye), 12 (bookworm), 13 (trixie). `amd64` o `arm64`. |
| Resto de scripts y Compose | Linux (o Docker Desktop) con Docker Engine + plugin `docker compose` |
| Versión de Zabbix | Fija en las imágenes `alpine-7.0-latest`, independiente del Debian del host |

No es “cualquier Debian”: Docker ya no publica repo estable para Debian 10 o anterior. Derivados (Mint, Kali, etc.) no están soportados: el script exige `ID=debian`.

---

## Contraseñas

Hay **dos contraseñas distintas**:

| Dónde | Usuario | Contraseña | Se configura en |
| --- | --- | --- | --- |
| PostgreSQL | el de `POSTGRES_USER` (por defecto `zabbix`) | `POSTGRES_PASSWORD` en `.env` | Primera vez: `.env` antes de `./install.sh`. Después: `./change-db-password.sh` |
| Interfaz web | `Admin` | `zabbix` | No está en `.env`. Cámbiala en Zabbix después del primer login |

**No edites solo `.env` para rotar Postgres** si el stack ya arrancó: el volumen ya tiene la clave vieja y Zabbix deja de conectar. Usa el script de abajo.

---

## Archivos del repo

| Archivo | Para qué |
| --- | --- |
| `.env` | Contraseña de Postgres y puertos. **No va a git** (`.gitignore`) |
| `env.example` | Plantilla pública (se ve en Finder; no empieza con punto) |
| `docker-compose.yml` | Postgres, Zabbix server, web y agente |
| `prepare.sh` | Docker + Compose en Debian 11–13 |
| `install.sh` | Levanta / para / resetea Zabbix |
| `backup.sh` | Dump de la base ahora |
| `schedule-backup.sh` | Cron; se puede repetir y reemplaza el horario anterior |
| `change-db-password.sh` | Cambia la clave de PostgreSQL sin borrar datos |
| `wipe.sh` | Borra datos / dumps / imágenes de este stack |
| `INSTRUCCIONES.md` | Esta guía |
| `README.md` | Portada del repo / portafolio |
| `LICENSE` | MIT |
| `.gitignore` | Ignora `.env` y `backups/` |

Al clonar, copia `env.example` a `.env`. No subas `.env` ni `backups/*.sql.gz`.

---

## En la Mac (antes de copiar)

1. Edita `.env` y cambia:

   `POSTGRES_PASSWORD=CHANGE_ME`

   por tu clave.

2. Sube la carpeta al Debian (FileZilla, `scp` o `rsync`), por ejemplo:

   ```bash
   rsync -av /Users/danielgonzalezfranco/Proyects/zabbix-docker/ usuario@IP-DEL-SERVER:~/zabbix-docker/
   ```

---

## En el servidor Debian 11, 12 o 13

### 1. Entrar y comprobar archivos

```bash
ssh usuario@IP-DEL-SERVER
cd ~/zabbix-docker
ls -la
```

Deben verse al menos: `.env`, `docker-compose.yml`, `prepare.sh`, `install.sh`.

### 2. Permisos (FileZilla a veces los quita)

```bash
chmod +x prepare.sh install.sh backup.sh schedule-backup.sh change-db-password.sh wipe.sh
```

### 3. Confirmar la clave de Postgres

```bash
nano .env
```

`POSTGRES_PASSWORD` no debe quedar en `CHANGE_ME`. Guardar: `Ctrl+O`, Enter, `Ctrl+X`.

Opcional en `.env`:

- `ZABBIX_WEB_PORT=8080` — puerto de la web
- `ZABBIX_SERVER_PORT=10051` — puerto para agentes
- `BACKUP_KEEP=14` — cuántos dumps conservar

### 4. Instalar Docker (solo una vez)

```bash
sudo ./prepare.sh
```

Cuando termine, **cierra la sesión SSH y vuelve a entrar** (grupo `docker`). Si no, `docker` pedirá sudo o fallará.

### 5. Levantar Zabbix

```bash
cd ~/zabbix-docker
./install.sh
```

Espera a que baje imágenes y arranque. La primera vez tarda.

### 6. Abrir la interfaz

En el navegador:

`http://IP-DEL-SERVER:8080`

- Usuario: `Admin`
- Contraseña: `zabbix`

Cámbiala en **Administration → Users**.

Si no carga: firewall del VPS o del hosting. Hay que abrir **8080** (web) y **10051** si van a conectar agentes desde otras máquinas.

### Comandos de Zabbix

```bash
./install.sh status    # estado
./install.sh logs      # logs
./install.sh down      # parar (conserva la base)
./install.sh           # volver a arrancar
./install.sh reset     # BORRA la base y deja instalación nueva
./wipe.sh              # menú para borrar más (dumps, cron, imágenes)
```

---

## Cambiar la contraseña de la base (sin reinstalar)

Si Zabbix ya está corriendo, **no** basta con editar `.env`. Hay que cambiarla dentro de PostgreSQL y recrear server/web.

```bash
./change-db-password.sh
```

Pide la clave dos veces, actualiza `.env` y reinicia `zabbix-server` y `zabbix-web`. **No borra datos.**

También puedes pasarla en el comando (se verá en el historial de shell; mejor el modo interactivo):

```bash
./change-db-password.sh 'TuNuevaClave'
```

Eso **no** cambia el login web `Admin`. Eso se cambia en la UI de Zabbix.

Evita `$` y backticks en la clave de Postgres (rompen Compose).

---

## Backups de PostgreSQL

### Dónde se guardan

En el **mismo servidor Debian**, en una carpeta del proyecto. No van a la Mac, ni a la nube, ni dentro de PostgreSQL.

Ruta:

```text
~/zabbix-docker/backups/
```

(Si copiaste el proyecto a otra ruta, será `<esa-carpeta>/backups/`.)

Cada copia es un archivo aparte:

```text
zabbix-AAAAMMDD-HHMMSS.sql.gz
```

Ejemplo: `backups/zabbix-20260910-030000.sql.gz`

Es un **dump SQL comprimido** (export de la base). No es el volumen Docker `postgres_data` (ese es la base en vivo). El dump es una copia en disco, junto a los scripts.

El log de cada ejecución queda en `backups/backup.log`.

Por defecto se conservan los últimos 14 dumps (`BACKUP_KEEP` en `.env`). Los más viejos se borran solos.

Si el disco o el server se pierden, se pierden estos backups. Para sacarlos, cópialos con FileZilla o `scp` a otro sitio.

Puedes ejecutar `./schedule-backup.sh` **las veces que quieras**. Cada ejecución **reemplaza** el horario anterior: no se acumulan crons. Hoy cada 60 minutos, mañana cada 2 días, no hay problema.

### Un backup ahora

```bash
./backup.sh
```

### Programar cada cuánto (menú)

```bash
./schedule-backup.sh
```

Opciones: 60 minutos, 6 horas, diario, cada 2 días, semanal, quitar, backup ahora, ver horario.

Sin menú:

```bash
./schedule-backup.sh every 60 minutes
./schedule-backup.sh every 6 hours
./schedule-backup.sh every 2 days
./schedule-backup.sh status
./schedule-backup.sh off
./schedule-backup.sh now
```

Hora personalizada (cron). Ejemplo, todos los días a las 04:30:

```bash
./schedule-backup.sh cron "30 4 * * *"
```

La hora es la **del servidor**. Compruébala con `date`.

Si `crontab` no existe:

```bash
sudo apt-get install -y cron
sudo systemctl enable --now cron
```

Luego vuelve a `./schedule-backup.sh`.

### Restaurar un dump (cuidado: pisa la base)

Zabbix debe estar parado o al menos Postgres accesible. Ejemplo:

```bash
gunzip -c backups/zabbix-20260910-030000.sql.gz | docker exec -i zabbix-postgres psql -U zabbix -d zabbix
```

Ajusta usuario/base si los cambiaste en `.env`. Hazlo solo si sabes que quieres reemplazar datos.

---

## Apagar o reiniciar el servidor

No hace falta parar Docker a mano si apagas **bien** el Debian:

```bash
sudo shutdown -h now
```

o `sudo reboot`. systemd detiene Docker y Postgres cierra ordenado. En Compose los servicios tienen `restart: unless-stopped`: al encender, los contenedores **vuelven solos**. No hace falta `./install.sh` en cada boot.

`./install.sh down` solo si quieres que **no** arranquen al prender; entonces al volver ejecutas `./install.sh`.

Evita cortar la corriente o “power off” forzado del panel. Postgres suele recuperarse, pero un shutdown limpio es lo correcto.

---

## Borrar todo si algo sale mal

Hay niveles. Elige el más pequeño que te sirva. **Todo esto borra datos de Zabbix** salvo “solo parar”.

### 0) Solo parar (no borra la base)

```bash
./install.sh down
```

Para contenedores. El volumen de Postgres sigue. `./install.sh` los vuelve a levantar.

### 1) Empezar Zabbix de cero (borra la base)

Úsalo si te equivocaste en `.env` (`POSTGRES_DB`, clave, etc.) o la instalación quedó a medias.

```bash
cd ~/zabbix-docker
./install.sh reset
# o: ./wipe.sh data
```

Corrige `.env` y:

```bash
./install.sh
```

La web vuelve a `Admin` / `zabbix`.

### 2) Base + dumps + cron de backup

Si además quieres tirar copias locales y la programación:

```bash
./wipe.sh stack
```

Luego `./install.sh` y, si quieres, `./schedule-backup.sh` otra vez.

### 3) Todo este proyecto en Docker (base + dumps + cron + imágenes)

Si los contenedores están rotos o quieres forzar descarga limpia de imágenes. **No** desinstala Docker.

```bash
./wipe.sh images
```

Luego:

```bash
./install.sh
```

### 4) Quitar también Docker del Debian (nuclear)

Solo si quieres dejar el server como antes de `prepare.sh`. Pierdes **todos** los contenedores de esa máquina, no solo Zabbix.

```bash
cd ~/zabbix-docker
./wipe.sh images
./schedule-backup.sh off

sudo systemctl stop docker
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
sudo apt-get autoremove -y
sudo rm -rf /var/lib/docker /var/lib/containerd
sudo rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
```

La carpeta `~/zabbix-docker` (scripts y `.env`) **sigue en disco**. Bórrala a mano si tampoco la quieres:

```bash
rm -rf ~/zabbix-docker
```

Para volver a instalar: copias el proyecto otra vez, `sudo ./prepare.sh`, logout/login, `./install.sh`.

### Qué se borra y qué no

| Cosa | `down` | `reset` / `wipe.sh data` | `wipe.sh stack` | `wipe.sh images` | purge Docker |
| --- | --- | --- | --- | --- | --- |
| Contenedores Zabbix | paran | se eliminan | se eliminan | se eliminan | se eliminan |
| Volumen Postgres (datos) | no | sí | sí | sí | sí |
| Carpeta `backups/` | no | no | sí | sí | no (salvo que borres la carpeta) |
| Cron de backup | no | no | sí | sí | no (quita con `./schedule-backup.sh off`) |
| Imágenes Docker | no | no | no | sí | sí |
| Docker Engine | no | no | no | no | sí |
| Archivos del repo (`.env`, scripts) | no | no | no | no | no |

---

## Problemas frecuentes

**`permission denied` al ejecutar scripts**  
`chmod +x prepare.sh install.sh backup.sh schedule-backup.sh change-db-password.sh wipe.sh`

**`Cannot connect to the Docker daemon` después de prepare.sh**  
Cierra SSH, entra otra vez. O: `sudo systemctl start docker`

**Web no abre**  
`./install.sh status` y `./install.sh logs`. Revisa firewall puerto 8080.

**Cambié `POSTGRES_PASSWORD` a mano en `.env` y Zabbix no conecta**  
Usa `./change-db-password.sh` (cambia Postgres + `.env` + recrea web/server). Si ya rompiste la conexión, pon en `.env` la clave **actual** de Postgres y recrea: `docker compose up -d --force-recreate --no-deps zabbix-server zabbix-web`. `./install.sh reset` borra datos; no hace falta para rotar clave.

**Login web**  
Siempre nace como `Admin` / `zabbix`. No es la de Postgres.

---

## Publicar en git (portafolio)

1. Confirma que `.env` no está en el commit (`git status`). Debe ignorarse.
2. No subas `backups/` ni dumps.
3. En GitHub/GitLab crea un repo **privado** si el `.env` alguna vez se filtró; si solo está `env.example`, puede ser público.
4. En el README del perfil enlaza este repo y menciona: Compose, Postgres, backups con cron, rotación de secretos, wipe.

Este stack es un **lab**. En un trabajo real: claves fuertes, HTTPS (reverse proxy), backups fuera del server y `Admin` cambiado al primer login.

