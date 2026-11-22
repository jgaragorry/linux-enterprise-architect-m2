# Runbook: Particiones lógicas, filesystems y montaje permanente en /dev/sdc

![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![Tool](https://img.shields.io/badge/Tool-fdisk-0A66C2?style=flat-square)
![Filesystems](https://img.shields.io/badge/ext3%20%7C%20ext4%20%7C%20XFS%20%7C%20swap-2EA44F?style=flat-square)
![Requires](https://img.shields.io/badge/Requires-sudo-8250DF?style=flat-square)

Este documento se sigue en orden, de arriba hacia abajo. Cada fase tiene un objetivo, los comandos exactos, la explicación de cada pieza y una verificación. Si la verificación no da lo esperado, nos detenemos ahí y revisamos antes de continuar.

Convención: las líneas que empiezan con `$` las escribimos nosotros. Lo que viene debajo, sin `$`, es lo que esperamos que responda el sistema. Los tamaños pueden variar unos pocos MB.

## Índice

| Fase | Tema | Riesgo |
|------|------|--------|
| 1 | Entorno: privilegios y herramientas | Ninguno |
| 2 | Agregar los discos en VMware | Bajo |
| 3 | Detectar los discos en Linux | Ninguno |
| 4 | Crear la partición extendida y las lógicas | Medio |
| 5 | Dar formato a cada partición | Medio |
| 6 | Montaje manual y migración de /home | Medio |
| 7 | Permisos de escritura | Bajo |
| 8 | Persistencia en /etc/fstab | Alto |
| 9 | Reinicio y validación final | Bajo |
| 10 | Limpieza para repetir el laboratorio | Medio |

## Antes de empezar: el mapa mental

Un disco con tabla MBR admite como máximo cuatro entradas primarias. Para tener más de cuatro particiones, una de esas entradas se convierte en **partición extendida**, que no guarda datos: es solo una caja. Dentro de esa caja se crean las **particiones lógicas**.

Por eso las numeraciones 1 a 4 están reservadas a las entradas primarias y las lógicas siempre empiezan en 5. En este laboratorio la extendida será `/dev/sdc1`, así que las lógicas serán `/dev/sdc5`, `/dev/sdc6`, `/dev/sdc7` y `/dev/sdc8`. Los números 2, 3 y 4 quedan libres y no existen como dispositivos.

Segundo concepto: una partición vacía todavía no sirve para guardar archivos. Necesita un **filesystem** (el formato), y ese filesystem debe **montarse** en un directorio. Montar es conectar el contenido de la partición a un directorio del árbol. Tres pasos, siempre en este orden: particionar, formatear, montar.

---

## Fase 1: Entorno, privilegios y herramientas

**Objetivo.** Confirmar que podemos administrar el sistema y que tenemos los programas que vamos a usar. Todavía no tocamos ningún disco.

### 1.1 Verificar acceso a sudo

Directorio: cualquiera.

```bash
$ sudo -v
```

- `sudo` ejecuta un comando con privilegios de administrador.
- `-v` (validate) solo valida tu contraseña y renueva el tiempo de sesión administrativa. No ejecuta nada más.

Verificación: te pide la contraseña, la escribes (no se ve mientras tecleas) y vuelve al prompt sin mensajes. Si responde que tu usuario no está en el archivo sudoers, no podemos seguir con esta cuenta.

### 1.2 Instalar las utilidades

```bash
$ sudo apt update
$ sudo apt install -y xfsprogs e2fsprogs util-linux parted
```

- `apt update` descarga la lista actualizada de paquetes desde los repositorios configurados. No instala nada, solo actualiza el catálogo.
- `apt install` instala los paquetes indicados. `-y` responde "sí" a la confirmación para que el proceso no se detenga.
- `xfsprogs` trae `mkfs.xfs`, para crear filesystems XFS.
- `e2fsprogs` trae `mkfs.ext3` y `mkfs.ext4`, para la familia ext.
- `util-linux` trae `lsblk`, `blkid`, `mount`, `mkswap` y `swapon`. En Ubuntu normalmente ya está instalado.
- `parted` trae `partprobe`, que usaremos para avisarle al kernel de cambios en la tabla de particiones. También sirve para inspeccionar discos.

Verificación:

```bash
$ mkfs.xfs -V
mkfs.xfs version 6.x.x
```

Cualquier versión que se imprima confirma que quedó instalado. Comprobamos el resto de una vez:

```bash
$ which mkfs.ext3 mkfs.ext4 mkswap partprobe
/usr/sbin/mkfs.ext3
/usr/sbin/mkfs.ext4
/usr/sbin/mkswap
/usr/sbin/partprobe
```

`which` imprime la ruta de cada ejecutable. Si alguno no aparece, repite la instalación.

---

## Fase 2: Agregar los dos discos de 4 GB en VMware

**Objetivo.** Dar a la máquina virtual dos discos nuevos y vacíos. Trabajaremos sobre el segundo, pero agregamos dos para que veas que el nombre `/dev/sdc` depende del orden de detección y no es un dato fijo.

### 2.1 Snapshot (recomendado)

Con la VM encendida o apagada, en VMware abre el menú de la VM, entra a Snapshot y toma uno con el nombre `antes-de-discos`. Sirve para volver al punto de partida y repetir el laboratorio.

### 2.2 Agregar los discos

1. Apaga la VM por completo: `sudo poweroff`. Un reinicio no basta, necesitamos que esté apagada.
2. En VMware abre la configuración de la VM (Edit virtual machine settings).
3. Haz clic en **Add**, elige **Hard Disk** y sigue el asistente.
4. Cuando pregunte el tamaño, escribe **4 GB**. Deja el tipo de disco que sugiera por defecto. Termina el asistente.
5. Repite los pasos 3 y 4 para el segundo disco.
6. Enciende la VM e inicia sesión.

Si el asistente ofrece "Store virtual disk as a single file" o "Split into multiple files", cualquiera de las dos sirve para este laboratorio.

Verificación: en la ventana de configuración de la VM deben verse tres discos: el original y dos de 4 GB.

---

## Fase 3: Detectar los discos en Linux

**Objetivo.** Identificar sin ambigüedad cuál es el disco con el que vamos a trabajar. Un error aquí es el más caro de todo el laboratorio, porque `fdisk` y `mkfs` sobrescriben lo que haya.

```bash
$ lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
```

- `lsblk` lista los dispositivos de bloque en forma de árbol.
- `-o` elige las columnas: `NAME` (nombre), `SIZE` (tamaño), `TYPE` (disk, part, etc.), `FSTYPE` (sistema de archivos, si lo tiene) y `MOUNTPOINT` (dónde está montado).

Salida esperada, con diferencias menores según tu instalación:

```text
NAME   SIZE TYPE FSTYPE MOUNTPOINT
sda     40G disk
├─sda1   1M part
└─sda2  40G part ext4   /
sdb      4G disk
sdc      4G disk
```

Cómo leerla:

- `sda` es el disco del sistema: tiene particiones y un punto de montaje `/`. No lo tocamos.
- `sdb` y `sdc` son los discos nuevos: 4G, tipo `disk`, sin particiones, sin FSTYPE y sin MOUNTPOINT.

Condiciones que debe cumplir `/dev/sdc` antes de seguir: tamaño 4G, sin hijos y sin punto de montaje. Si el tuyo muestra otro nombre, por ejemplo que los discos nuevos son `sdb` y `sdd`, usa el nombre real en todos los comandos de aquí en adelante.

Segunda comprobación, más estricta:

```bash
$ sudo blkid /dev/sdc
```

`blkid` imprime el tipo y el UUID de un dispositivo. Aquí esperamos **ninguna salida**, que significa que el disco no tiene firma de filesystem.

---

## Fase 4: Crear la partición extendida y las cuatro lógicas

**Objetivo.** Dejar `/dev/sdc` con una extendida (`sdc1`) que ocupa todo el disco y cuatro lógicas dentro (`sdc5` a `sdc8`).

### 4.1 Abrir fdisk

```bash
$ sudo fdisk /dev/sdc
```

`fdisk` es un editor interactivo de tablas de particiones. Los cambios quedan en memoria hasta que escribimos `w`. Si algo sale mal antes de `w`, se sale con `q` y el disco queda intacto.

El prompt cambia a `Command (m for help):`. Ahí se escriben las letras y se presiona Enter.

### 4.2 Crear la tabla MBR y la partición extendida

Escribe estas teclas en orden:

| Tecla | Qué hace |
|-------|----------|
| `o` | Crea una tabla de particiones DOS (MBR) vacía |
| `n` | Nueva partición |
| `e` | Tipo extendida |
| Enter | Acepta el número por defecto: 1 |
| Enter | Acepta el primer sector por defecto |
| Enter | Acepta el último sector por defecto, de modo que la extendida ocupe todo el disco |

Aceptar el último sector por defecto es lo que hace que la caja use los 4 GB completos.

Verificación parcial, todavía dentro de fdisk:

```text
Command (m for help): p
...
Device     Boot Start     End Sectors Size Id Type
/dev/sdc1        2048 8388607 8386560   4G  5 Extended
```

`p` imprime la tabla en memoria. Debe aparecer una sola línea, de tipo `Extended`.

### 4.3 Crear las lógicas sdc5, sdc6 y sdc7

Repite este bloque tres veces:

| Tecla | Qué hace |
|-------|----------|
| `n` | Nueva partición |
| `l` | Tipo lógica. Aparece como opción porque ya existe la extendida |
| Enter | Acepta el número automático (5, luego 6, luego 7) |
| Enter | Acepta el primer sector por defecto |
| `+1G` | Tamaño: 1 gigabyte. El signo `+` significa "este tamaño a partir del inicio" |

### 4.4 Crear la cuarta lógica (sdc8)

Aquí hay una diferencia con las anteriores. Cada lógica consume un pequeño espacio extra para su propia cabecera (una estructura llamada EBR), y la extendida ya tiene un margen inicial de alineación. Por eso, después de crear tres de 1 GB exactos, la cuarta ya no cabe en un `+1G` exacto: quedan unos pocos MB menos de 1 GB disponibles.

Si escribes `+1G` y fdisk responde `Value out of range`, es esperado. Haz esto:

| Tecla | Qué hace |
|-------|----------|
| `n` | Nueva partición |
| `l` | Lógica |
| Enter | Número automático: 8 |
| Enter | Primer sector por defecto |
| Enter | Último sector por defecto: usa todo lo que quede, un poco menos de 1 GB |

Para una partición swap eso no importa.

### 4.5 Revisar y escribir

```text
Command (m for help): p
```

Debe verse algo así:

```text
Device     Boot   Start     End Sectors  Size Id Type
/dev/sdc1          2048 8388607 8386560    4G  5 Extended
/dev/sdc5          4096 2101247 2097152    1G 83 Linux
/dev/sdc6       2103296 4200447 2097152    1G 83 Linux
/dev/sdc7       4202496 6299647 2097152    1G 83 Linux
/dev/sdc8       6301696 8388607 2086912 1019M 83 Linux
```

Si la tabla coincide, escribe `w`. Esto guarda los cambios en el disco y sale de fdisk. Si hay algo raro, escribe `q` para salir sin guardar y repite desde 4.1.

Sobre el tipo de la `sdc8`: fdisk le asigna el tipo `83 Linux`. Para swap existe el tipo `82`, que se cambia con `t`, pero no es necesario: `mkswap` y `swapon` no dependen de ese código. Si prefieres dejarlo correcto, dentro de fdisk antes de `w`, escribe `t`, elige la partición `8` y el código `82`.

### 4.6 Avisar al kernel

```bash
$ sudo partprobe /dev/sdc
```

`partprobe` le pide al kernel que vuelva a leer la tabla de particiones de `/dev/sdc`. Sin esto, a veces los nodos `/dev/sdc5` a `/dev/sdc8` no aparecen hasta reiniciar.

Verificación:

```bash
$ lsblk /dev/sdc
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sdc      8:32   0    4G  0 disk
├─sdc1   8:33   0    1K  0 part
├─sdc5   8:37   0    1G  0 part
├─sdc6   8:38   0    1G  0 part
├─sdc7   8:39   0    1G  0 part
└─sdc8   8:40   0 1019M  0 part
```

`sdc1` aparece con tamaño de 1K porque es la caja y no almacena datos. Los números 2, 3 y 4 no existen. Es correcto.

---

## Fase 5: Dar formato a cada partición

**Objetivo.** Crear un filesystem distinto en cada lógica. La opción de forzar (`-F` o `-f`) la usamos porque estamos formateando particiones nuevas y no queremos que la herramienta pregunte por cada una.

Plan:

| Partición | Formato | Destino |
|-----------|---------|---------|
| `/dev/sdc5` | ext3 | `/var/www` |
| `/dev/sdc6` | ext4 | `/home` |
| `/dev/sdc7` | XFS | `/fs_storage` |
| `/dev/sdc8` | swap | sin directorio |

### 5.1 ext3 en sdc5

```bash
$ sudo mkfs.ext3 -F /dev/sdc5
```

- `mkfs.ext3` crea un filesystem ext3, la tercera generación de la familia ext y la primera en incluir journal (un registro de cambios pendientes que ayuda a recuperar el sistema tras un corte de energía).
- `-F` (mayúscula) fuerza la creación. La herramienta suele pedir confirmación en casos que considera dudosos.

### 5.2 ext4 en sdc6

```bash
$ sudo mkfs.ext4 -F /dev/sdc6
```

`mkfs.ext4` crea el filesystem ext4, el estándar en la mayoría de instalaciones Ubuntu. Mismo `-F` que arriba.

### 5.3 XFS en sdc7

```bash
$ sudo mkfs.xfs -f /dev/sdc7
```

`mkfs.xfs` crea el filesystem XFS, común en entornos enterprise por su buen rendimiento con archivos grandes. Aquí la opción de forzar es `-f` en **minúscula**: en XFS, `-F` significa otra cosa. Esa diferencia entre herramientas es típica y conviene tenerla presente.

### 5.4 Swap en sdc8

```bash
$ sudo mkswap /dev/sdc8
$ sudo swapon /dev/sdc8
```

- `mkswap` escribe en la partición la estructura de swap. Es el equivalente a "formatear" para intercambio.
- `swapon` activa esa swap de inmediato para que el sistema pueda usarla ya, sin reiniciar.

`mkswap` imprime el UUID de la partición. No hace falta copiarlo ahora, lo consultaremos más adelante.

### 5.5 Verificación de la fase

```bash
$ lsblk -f /dev/sdc
NAME   FSTYPE FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
sdc
├─sdc1
├─sdc5 ext3   1.0         xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
├─sdc6 ext4   1.0         xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
├─sdc7 xfs                xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
└─sdc8 swap   1           xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx [SWAP]
```

```bash
$ swapon --show
NAME      TYPE      SIZE USED PRIO
/dev/sdc8 partition 1019M   0B   -2
```

`lsblk -f` agrega el tipo de filesystem y el UUID. `swapon --show` lista las áreas de intercambio activas. Deben coincidir con el plan: ext3, ext4, xfs y swap.

---

## Fase 6: Montaje manual y migración de /home

**Objetivo.** Conectar cada filesystem a su directorio. Primero lo hacemos a mano, sin tocar `/etc/fstab`, porque así los errores se corrigen desmontando y no comprometen el arranque.

### 6.1 Crear los directorios de destino

```bash
$ sudo mkdir -p /var/www /fs_storage
```

`mkdir` crea directorios. `-p` crea también los directorios padre si faltan y no da error si el directorio ya existe. `/home` no se crea porque ya existe en cualquier instalación de Ubuntu.

### 6.2 Montar sdc5 y sdc7

```bash
$ sudo mount /dev/sdc5 /var/www
$ sudo mount /dev/sdc7 /fs_storage
```

`mount DISPOSITIVO DIRECTORIO` conecta el filesystem al directorio. A partir de este momento, lo que escribas en `/var/www` se guarda en `sdc5`. El tipo de filesystem lo detecta `mount` leyendo la partición.

### 6.3 Por qué /home necesita un paso adicional

Este punto es importante para entender cómo funciona un montaje. Cuando montas algo sobre un directorio que ya tiene contenido, ese contenido **no se borra**, pero queda **oculto** mientras el montaje esté activo. `/home` ya contiene la carpeta de tu usuario con tu configuración y tus archivos. Si montamos `sdc6` encima sin más, entrarías con una carpeta personal vacía, y en un login gráfico eso suele terminar en un error de sesión.

Por eso primero copiamos el contenido actual a la partición nueva, y luego la montamos sobre `/home`.

**Paso 1.** Montar `sdc6` de forma temporal en un directorio auxiliar:

```bash
$ sudo mkdir -p /mnt/newhome
$ sudo mount /dev/sdc6 /mnt/newhome
```

`/mnt` es el lugar convencional para montajes temporales.

**Paso 2.** Copiar los datos preservando todo:

```bash
$ sudo rsync -aHAX /home/ /mnt/newhome/
```

- `rsync` copia archivos y directorios de forma eficiente.
- `-a` (archive) conserva permisos, dueños, fechas y enlaces simbólicos, y copia de forma recursiva.
- `-H` conserva los enlaces duros.
- `-A` conserva las ACL (permisos extendidos).
- `-X` conserva los atributos extendidos.
- La barra final en `/home/` y `/mnt/newhome/` importa: significa "copia el **contenido** de este directorio" y no el directorio en sí.

Si `rsync` no está instalado: `sudo apt install -y rsync`.

**Paso 3.** Comprobar que la copia se hizo:

```bash
$ ls -la /mnt/newhome
```

Debes ver la carpeta de tu usuario (`/mnt/newhome/tu_usuario`) y, dentro de ella, tus archivos.

**Paso 4.** Desmontar el punto temporal y montar `sdc6` en su lugar definitivo:

```bash
$ sudo umount /mnt/newhome
$ sudo mount /dev/sdc6 /home
```

`umount` desconecta un filesystem (se escribe sin la "n" de "unmount"). Ahora `/home` es `sdc6`.

### 6.4 Verificación

```bash
$ df -hT /var/www /home /fs_storage
Filesystem     Type  Size  Used Avail Use% Mounted on
/dev/sdc5      ext3  974M   24K  923M   1% /var/www
/dev/sdc6      ext4  974M  ...
/dev/sdc7      xfs  1014M   ...
```

`df` muestra el uso de disco. `-h` usa unidades legibles (G, M) y `-T` agrega la columna de tipo de filesystem. La columna `Type` debe decir ext3, ext4 y xfs, y la columna `Filesystem` debe mostrar `sdc5`, `sdc6` y `sdc7` en ese orden. Los tamaños son un poco menores a 1 GB porque parte del espacio se reserva para las estructuras internas de cada filesystem.

Si algún `Filesystem` aparece como `/dev/sda2` o similar, ese montaje no se hizo. Revisa el comando de montaje correspondiente.

---

## Fase 7: Permisos de escritura

**Objetivo.** Poder escribir en los directorios montados.

Dos aclaraciones que explican el orden de esta fase:

1. Los permisos hay que aplicarlos **después** de montar. Al montar, el directorio pasa a mostrar los permisos del filesystem nuevo (la raíz de la partición), no los que tenía el directorio vacío antes. Si hubiéramos hecho el `chmod` en la fase anterior, se habría perdido.
2. `/home` **no** se abre con permisos 777. Es un error frecuente en laboratorios: OpenSSH, por ejemplo, rechaza las llaves de un usuario si su carpeta personal es escribible por otros. `/home` queda como estaba, con dueño `root` y permisos `755`, y cada usuario escribe dentro de su propia carpeta.

### 7.1 Permisos en /var/www y /fs_storage

```bash
$ sudo chmod 777 /var/www /fs_storage
```

`chmod` cambia los permisos. `777` da lectura, escritura y ejecución a dueño, grupo y otros. Sin `-R`, porque solo necesitamos abrir la raíz del montaje: en `/var/www` y `/fs_storage` solo existe `lost+found` (en los ext) y ningún otro dato que tocar.

Esto es una comodidad para el laboratorio. En un servidor real definimos un dueño y un grupo concretos, por ejemplo `chown root:www-data /var/www` con `chmod 775`.

### 7.2 Comprobar permisos de /home

```bash
$ ls -ld /home
drwxr-xr-x 3 root root 4096 ... /home
```

`ls -ld` muestra los permisos del directorio en sí y no los de su contenido. Debe verse `drwxr-xr-x` con dueño `root`.

### 7.3 Prueba de escritura

```bash
$ echo "prueba ext3 en sdc5" | sudo tee /var/www/test_www.txt
$ echo "prueba xfs en sdc7"  | sudo tee /fs_storage/test_xfs.txt
$ echo "prueba ext4 en sdc6"  > ~/test_home.txt
```

- `echo` imprime un texto.
- `|` (pipe) pasa la salida del comando de la izquierda como entrada al de la derecha.
- `tee` escribe esa entrada en el archivo indicado y además la muestra en pantalla. Lo usamos con `sudo` porque la redirección `>` la hace tu shell sin privilegios, y `sudo echo ... > archivo` no funciona.
- La tercera línea escribe dentro de tu propia carpeta personal, que ahora vive en `sdc6`, sin `sudo`. Esa es la prueba más representativa para `/home`.

Verificación:

```bash
$ cat /var/www/test_www.txt /fs_storage/test_xfs.txt ~/test_home.txt
prueba ext3 en sdc5
prueba xfs en sdc7
prueba ext4 en sdc6
```

---

## Fase 8: Persistencia en /etc/fstab

**Objetivo.** Los montajes de la fase 6 se pierden al reiniciar. `/etc/fstab` es el archivo que el sistema lee en el arranque para saber qué montar y dónde. Es el paso con más riesgo del laboratorio: una línea mal escrita puede dejar el sistema en modo de emergencia al arrancar. Por eso lo hacemos con respaldo, y lo probamos antes de reiniciar.

### 8.1 Obtener los UUID

```bash
$ sudo blkid /dev/sdc5 /dev/sdc6 /dev/sdc7 /dev/sdc8
/dev/sdc5: UUID="aaaa..." TYPE="ext3" ...
/dev/sdc6: UUID="bbbb..." TYPE="ext4" ...
/dev/sdc7: UUID="cccc..." TYPE="xfs" ...
/dev/sdc8: UUID="dddd..." TYPE="swap" ...
```

Usamos UUID y no `/dev/sdc5` porque los nombres `sdX` pueden cambiar si agregas o quitas discos o cambia el orden de detección. El UUID viaja con el filesystem y no cambia.

Para evitar errores de transcripción, copia los UUID con el mouse o genera las líneas automáticamente:

```bash
$ for p in 5 6 7 8; do echo "/dev/sdc$p  $(sudo blkid -s UUID -o value /dev/sdc$p)"; done
```

`blkid -s UUID -o value` imprime solo el valor del UUID, sin el resto de los campos.

### 8.2 Respaldar el archivo

```bash
$ sudo cp /etc/fstab /etc/fstab.bak.$(date +%F)
```

- `cp` copia el archivo.
- `$(date +%F)` se sustituye por la fecha de hoy en formato `2026-11-22`, así el respaldo queda identificado.

Verificación: `ls /etc/fstab.bak.*` debe mostrar el archivo.

### 8.3 Editar el archivo

```bash
$ sudo nano /etc/fstab
```

Ve al final del archivo y agrega estas cuatro líneas, reemplazando cada `UUID_DE_SDCx` con el UUID real:

```text
UUID=UUID_DE_SDC5  /var/www      ext3  defaults  0  2
UUID=UUID_DE_SDC6  /home         ext4  defaults  0  2
UUID=UUID_DE_SDC7  /fs_storage   xfs   defaults  0  0
UUID=UUID_DE_SDC8  none          swap  sw        0  0
```

Guarda con `Ctrl + O` y Enter, y sal con `Ctrl + X`.

Cada línea tiene seis campos separados por espacios:

| Campo | Significado | En nuestro caso |
|-------|-------------|-----------------|
| 1 | Qué se monta: dispositivo o UUID | `UUID=...` |
| 2 | Dónde se monta | `/var/www`, `/home`, `/fs_storage`; `none` para swap |
| 3 | Tipo de filesystem | `ext3`, `ext4`, `xfs`, `swap` |
| 4 | Opciones de montaje | `defaults` equivale a lectura y escritura, ejecución, `suid`, etc. Para swap, `sw` |
| 5 | `dump`: respaldo con la herramienta dump | `0`, desactivado |
| 6 | `pass`: orden de chequeo de filesystem en arranque | `2` para ext3 y ext4 (la raíz usa `1`); `0` para XFS y swap, que no se revisan con `fsck` |

### 8.4 Probar antes de reiniciar

Primero desmontamos todo lo que montamos a mano, y luego dejamos que `/etc/fstab` lo monte. Así la prueba es real.

```bash
$ sudo swapoff /dev/sdc8
$ sudo umount /var/www /home /fs_storage
$ sudo systemctl daemon-reload
$ sudo mount -a
$ sudo swapon -a
```

- `swapoff` desactiva la swap que activamos a mano.
- `umount` desmonta los tres directorios. Si `/home` responde `target is busy`, es porque tu sesión está usando archivos de ahí. Cierra otras terminales, usa una consola de texto (`Ctrl + Alt + F3`) o salta directamente al reinicio de la fase 9 y valida allí.
- `systemctl daemon-reload` hace que `systemd` relea `/etc/fstab`. Ubuntu convierte cada línea en una unidad interna, y sin este paso a veces usa la versión anterior.
- `mount -a` monta todo lo que esté en `/etc/fstab` y todavía no esté montado. Si hay un error de sintaxis, aparece aquí y no en el arranque.
- `swapon -a` activa todas las swap que figuren en `/etc/fstab`.

Verificación:

```bash
$ df -hT /var/www /home /fs_storage
$ swapon --show
```

Los resultados deben ser iguales a los de la fase 6. Si `mount -a` imprime un error, restaura el respaldo antes de hacer cualquier otra cosa:

```bash
$ sudo cp /etc/fstab.bak.FECHA /etc/fstab
```

Sustituye `FECHA` por la del respaldo que hiciste en 8.2.

---

## Fase 9: Reinicio y validación final

**Objetivo.** Probar la persistencia como ocurre en la vida real: apagar y volver a encender.

```bash
$ sudo reboot
```

Al volver a iniciar sesión:

```bash
$ df -hT /var/www /home /fs_storage
$ swapon --show
$ lsblk -f /dev/sdc
$ cat /var/www/test_www.txt /fs_storage/test_xfs.txt ~/test_home.txt
```

Lista de comprobación para dar el laboratorio por terminado:

- [ ] `/var/www` está montado desde `/dev/sdc5` con tipo `ext3`.
- [ ] `/home` está montado desde `/dev/sdc6` con tipo `ext4`.
- [ ] `/fs_storage` está montado desde `/dev/sdc7` con tipo `xfs`.
- [ ] `swapon --show` lista `/dev/sdc8`.
- [ ] Los tres archivos de prueba se leen con su contenido original.
- [ ] Puedes iniciar sesión con normalidad y tu carpeta personal tiene tus archivos.

Si falta algo, el diagnóstico es siempre el mismo: `lsblk -f` para ver qué UUID tiene realmente cada partición, `cat /etc/fstab` para comparar, y `sudo journalctl -b | grep -i mount` para ver qué dijo el sistema durante el arranque.

---

## Fase 10: Limpieza para repetir el laboratorio

**Objetivo.** Dejar `/dev/sdc` vacío y el sistema como estaba. Hazlo solo si quieres practicar la limpieza. Si tienes el snapshot, revertir a él es más rápido.

### 10.1 Desactivar y desmontar

```bash
$ sudo swapoff /dev/sdc8
$ sudo umount /var/www /fs_storage /home
```

Al desmontar `/home`, el directorio vuelve a mostrar el contenido original que había quedado oculto debajo. Si cerraste sesión y volviste a entrar durante el laboratorio, ese contenido puede estar desactualizado respecto a la copia en `sdc6`. Para un laboratorio no importa.

### 10.2 Restaurar /etc/fstab

```bash
$ ls /etc/fstab.bak.*
$ sudo cp /etc/fstab.bak.FECHA /etc/fstab
$ sudo systemctl daemon-reload
```

Elige el respaldo de la fase 8.2. Después de esto el sistema ya no intenta montar nada de `sdc`.

### 10.3 Borrar firmas y tabla de particiones

```bash
$ sudo wipefs -a /dev/sdc8 /dev/sdc7 /dev/sdc6 /dev/sdc5
$ sudo wipefs -a /dev/sdc
$ sudo partprobe /dev/sdc
```

- `wipefs -a` borra las firmas de filesystem y de tabla de particiones del dispositivo indicado. No pone el disco a cero, pero hace que el sistema deje de reconocer lo que había.
- Se borra primero cada partición y al final el disco entero. Así no quedan firmas escondidas dentro de las particiones, y `fdisk` no te advertirá de que "detecta una firma anterior" cuando vuelvas a particionar.

Verificación:

```bash
$ lsblk /dev/sdc
NAME SIZE TYPE MOUNTPOINT
sdc    4G disk
```

Con el disco limpio y `/etc/fstab` restaurado, puedes volver a la fase 4.

### 10.4 Rehacer desde cero

Para empezar desde la fase 2, apaga la VM, elimina los dos discos desde la configuración de VMware (selecciona el disco y pulsa Remove) y vuelve a agregarlos. O revierte al snapshot `antes-de-discos`.

