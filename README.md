# Sistema de Gestión de Coworking — MySQL 2, Grupo 05

Base de datos MySQL que administra las operaciones de un coworking moderno: usuarios y membresías, reservas de espacios de trabajo, servicios adicionales, ventas, pagos y facturación, control de acceso con RFID/QR, asistencia y reportes financieros.

![Modelo lógico](docs/modelo_logico.png)

---

## Tabla de contenido

1. [Descripción del proyecto](#1-descripción-del-proyecto)
2. [Requisitos del sistema](#2-requisitos-del-sistema)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [Instalación y configuración](#4-instalación-y-configuración)
5. [Estructura de la base de datos](#5-estructura-de-la-base-de-datos)
6. [Ejemplos de consultas](#6-ejemplos-de-consultas)
7. [Procedimientos, funciones, triggers y eventos](#7-procedimientos-funciones-triggers-y-eventos)
8. [Roles de usuario y permisos](#8-roles-de-usuario-y-permisos)
9. [Contribuciones](#9-contribuciones)
10. [Licencia y contacto](#10-licencia-y-contacto)

---

## 1. Descripción del proyecto

**Nodo Coworking** es un coworking con varias sedes. La base de datos `coworking_grupo5` permite:

- **Usuarios y membresías.** Registro de personas y usuarios (con empresa, si aplica), membresías Diaria, Mensual, Corporativa y Premium, con estados Pendiente, Activa, Suspendida y Vencida. Las membresías son **acumulables**: comprar otra antes de que termine la actual extiende la vigencia.
- **Espacios y reservas.** Escritorios flexibles, oficinas privadas, salas de reuniones y salas de eventos, con capacidad, precio por hora y horarios de atención por sede. Las reservas validan disponibilidad, horario y capacidad, y pasan por los estados Pendiente → Confirmada → Finalizada (o Cancelada / No Show).
- **Servicios adicionales.** Internet premium, lockers, café ilimitado, impresiones, proyector y parqueadero, asociados al usuario (y a la reserva cuando aplica) y cobrados en su factura.
- **Pagos y facturación.** Ventas a nombre de un usuario o de una empresa (factura consolidada), pagos parciales con métodos Efectivo, Tarjeta, Transferencia y PayPal, estados Pagado, Pendiente y Cancelado, IVA del 19 %, recargos por mora, anulaciones y reembolsos.
- **Control de acceso y asistencia.** Entradas y salidas con tarjeta RFID o código QR, validando membresía activa, reserva confirmada y horario de la sede; historial de asistencias y registro de intentos rechazados.
- **Reportes y auditoría.** Reportes financieros mensuales, notificaciones (recordatorios, alertas, reportes) y un log de auditoría.

Además de la estructura y los datos, el proyecto incluye **100 consultas, 20 funciones, 20 procedimientos almacenados, 20 triggers, 20 eventos y 5 roles** con sus permisos.

---

## 2. Requisitos del sistema

| Software | Versión |
|---|---|
| MySQL Server | **8.0.16 o superior** (probado en 8.0.46). Se usan `CHECK`, roles, CTE recursivos, funciones de ventana (`OVER`), `JSON_TABLE`/`JSON_EXTRACT` y valores por defecto con expresiones. |
| Cliente | MySQL Workbench 8.0 o el cliente de consola `mysql` (los scripts de funciones, procedimientos y triggers usan `DELIMITER`). |
| Programador de eventos | `event_scheduler = ON` (lo activa `06_eventos/01_eventos.sql`). |
| Privilegios | Una cuenta con permisos de administración (por ejemplo `root`) para crear la base, rutinas, triggers, eventos, roles y usuarios. Con el binlog activo, crear funciones requiere `SUPER` o `log_bin_trust_function_creators = 1`. |

---

## 3. Estructura del repositorio

```
coworking-mysql2-grupo05/
├── README.md
├── docs/
│   ├── modelo_logico.png           Diagrama entidad-relación (modelo lógico)
│   └── roles_permisos.md           Detalle de roles, permisos y cuentas de ejemplo
└── sql/
    ├── 00_ddl/
    │   └── 01_estructura.sql        Base de datos, 25 tablas, restricciones e índices
    ├── 01_dml/
    │   └── 01_datos_iniciales.sql   Datos sintéticos coherentes
    ├── 02_consultas/
    │   ├── 01_usuarios_membresias.sql   Consultas 01-20
    │   ├── 02_espacios_reservas.sql     Consultas 21-40
    │   ├── 03_pagos_facturacion.sql     Consultas 41-60
    │   ├── 04_accesos_asistencias.sql   Consultas 61-80
    │   └── 05_consultas_avanzadas.sql   Consultas 81-100
    ├── 03_funciones/
    │   └── 01_funciones.sql             20 funciones (fn_)
    ├── 04_procedimientos/
    │   ├── 01_procedimientos.sql        20 procedimientos (sp_)
    │   └── 02_pruebas_procedimientos.sql
    ├── 05_triggers/
    │   ├── 01_triggers.sql              20 triggers (trg_)
    │   └── 02_pruebas_triggers.sql
    ├── 06_eventos/
    │   └── 01_eventos.sql               20 eventos (evt_)
    └── 07_seguridad/
        ├── 01_roles.sql                 5 roles (rol_)
        ├── 02_permisos.sql              Vistas de seguridad y GRANT
        └── 03_usuarios_ejemplo.sql      Una cuenta por rol
```

**Convenciones:** archivos en minúsculas sin espacios ni tildes; tablas y columnas en `snake_case`; prefijos `sp_` (procedimientos), `fn_` (funciones), `trg_` (triggers), `evt_` (eventos), `idx_` (índices secundarios) y `rol_` (roles). Cada archivo SQL empieza con una cabecera (proyecto, grupo, módulo, archivo, descripción y requisitos) y cada consulta o rutina tiene un bloque de comentario que explica qué hace.

---

## 4. Instalación y configuración

### 4.1 Orden de ejecución

Los scripts deben ejecutarse **en este orden**:

| Paso | Script | Qué hace |
|:-:|---|---|
| 1 | `sql/00_ddl/01_estructura.sql` | Crea la base `coworking_grupo5`, las tablas, restricciones e índices, y el catálogo de métodos de pago. |
| 2 | `sql/01_dml/01_datos_iniciales.sql` | Carga los datos iniciales. |
| 3 | `sql/03_funciones/01_funciones.sql` | Crea las 20 funciones. |
| 4 | `sql/04_procedimientos/01_procedimientos.sql` | Crea los 20 procedimientos. |
| 5 | `sql/05_triggers/01_triggers.sql` | Crea los 20 triggers. |
| 6 | `sql/06_eventos/01_eventos.sql` | Activa el programador y crea los 20 eventos. |
| 7 | `sql/07_seguridad/01_roles.sql`, `02_permisos.sql`, `03_usuarios_ejemplo.sql` | Roles, permisos y cuentas de ejemplo. |

> **Importante:** los triggers se crean **después** de cargar los datos. Si existieran durante la carga, el trigger que fuerza el estado inicial dejaría todas las reservas en PENDIENTE, el de solapamiento rechazaría los dos pares de reservas solapadas que se incluyen a propósito para la consulta 34, y los de accesos duplicarían asistencias y registros del log.

Para empezar de cero, descomenta la primera línea de `01_estructura.sql` (`DROP DATABASE IF EXISTS coworking_grupo5;`).

### 4.2 Desde la consola

Ubicado en la raíz del repositorio:

```bash
mysql -u root -p < sql/00_ddl/01_estructura.sql
mysql -u root -p < sql/01_dml/01_datos_iniciales.sql
mysql -u root -p < sql/03_funciones/01_funciones.sql
mysql -u root -p < sql/04_procedimientos/01_procedimientos.sql
mysql -u root -p < sql/05_triggers/01_triggers.sql
mysql -u root -p < sql/06_eventos/01_eventos.sql
mysql -u root -p < sql/07_seguridad/01_roles.sql
mysql -u root -p < sql/07_seguridad/02_permisos.sql
mysql -u root -p < sql/07_seguridad/03_usuarios_ejemplo.sql
```

También se puede hacer desde una sesión abierta del cliente con `SOURCE`:

```sql
SOURCE sql/00_ddl/01_estructura.sql;
SOURCE sql/01_dml/01_datos_iniciales.sql;
-- ... y así con el resto, en el orden de la tabla
```

### 4.3 Desde MySQL Workbench

1. Abre cada archivo con **File → Open SQL Script**.
2. Ejecútalo completo con el ícono del rayo (**Execute all**, `Ctrl + Shift + Enter`). Ejecutar solo la sentencia del cursor (`Ctrl + Enter`) insertaría únicamente un bloque.
3. Repite con el siguiente archivo, respetando el orden.

Workbench limita por defecto las consultas `SELECT` a 1.000 filas; los `INSERT` no tienen límite.

### 4.4 Fecha de referencia de los datos

Los datos están construidos alrededor del **jueves 1 de octubre de 2026** ("hoy" en los datos): hay reservas en curso ese día, membresías que vencen la semana siguiente, facturas que vencen en días concretos, etc. Las consultas usan `CURDATE()` y `NOW()`, así que en otra fecha devuelven los resultados de esa fecha.

Para reproducir exactamente el escenario de los datos, fija la fecha **solo en tu sesión** antes de ejecutar consultas o pruebas:

```sql
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');   -- NOW() y CURDATE() devuelven esa fecha
-- ... consultas ...
SET timestamp = DEFAULT;                                  -- volver a la fecha real
```

Los archivos de pruebas ya lo hacen. Los eventos se ejecutan en su propia sesión con la fecha real del servidor.

### 4.5 Ejecutar consultas, funciones, procedimientos y pruebas

- **Consultas:** abre el archivo del módulo en `sql/02_consultas/` y ejecuta cada consulta (`Ctrl + Enter` sobre ella) o el archivo completo. Cada una está numerada (`-- CONSULTA 01` ... `-- CONSULTA 100`).
- **Funciones:** se usan dentro de un `SELECT`, por ejemplo `SELECT fn_estado_membresia(44);`.
- **Procedimientos:** se ejecutan con `CALL`; los parámetros de salida se leen con variables: `CALL sp_verificar_disponibilidad(5, '2026-10-20 09:00', '2026-10-20 11:00', @ok, @motivo); SELECT @ok, @motivo;`.
- **Pruebas:** `sql/05_triggers/02_pruebas_triggers.sql` y `sql/04_procedimientos/02_pruebas_procedimientos.sql` prueban cada trigger y cada procedimiento. Cada bloque abre una transacción y termina en `ROLLBACK`, así que **no modifican los datos**. Los errores que aparecen están marcados como `ERROR esperado` (por ejemplo, intentar renovar una membresía suspendida).
- **Eventos:** se ejecutan solos según su programación. Para verlos: `SHOW EVENTS FROM coworking_grupo5;`. Para comprobar el programador: `SHOW VARIABLES LIKE 'event_scheduler';`.

> Al activarse, los eventos modifican los datos con la fecha real: por ejemplo, `evt_cancelar_reservas_pendientes` cancela en minutos las reservas PENDIENTES creadas hace más de 2 horas. Si quieres conservar el escenario de prueba intacto, crea los eventos al final o desactiva temporalmente el programador con `SET GLOBAL event_scheduler = OFF;`.

---

## 5. Estructura de la base de datos

25 tablas organizadas en seis grupos (ver `docs/modelo_logico.png`).

### Coworking, sedes y espacios
| Tabla | Propósito |
|---|---|
| `coworking` | La marca del coworking. |
| `sedes_coworking` | Sedes físicas de cada coworking. |
| `horarios_atencion` | Horario de apertura y cierre de cada sede por día de la semana. |
| `espacios` | Espacios reservables de cada sede: tipo, capacidad, precio por hora y estado. |
| `servicios` | Catálogo de servicios adicionales con su precio. |
| `servicio_espacio` | Qué servicios ofrece cada espacio (N:M). |

### Personas, empresas y usuarios
| Tabla | Propósito |
|---|---|
| `personas` | Datos personales: documento, nombres, apellidos, fecha de nacimiento y contacto. |
| `empresas` | Empresas cliente (NIT, razón social). |
| `empleados_empresa` | Vínculo persona–empresa (N:M) e indicador de gerente corporativo. |
| `usuarios` | Cuenta de cada persona en el coworking (1:1 con `personas`): usuario, contraseña (hash), código RFID/QR, último acceso y bloqueo de servicios. |

### Membresías y reservas
| Tabla | Propósito |
|---|---|
| `membresias` | Los 4 tipos de membresía y su precio. |
| `suscripciones` | Cada membresía comprada por un usuario, con fecha de inicio, fin (exclusiva) y estado. Guarda el historial completo. |
| `reservas` | Reservas de un usuario sobre un espacio, con horario, personas inscritas y estado. |
| `servicio_usuario` | Consumo de servicios adicionales de un usuario (y la reserva en la que se usó, si aplica). |

### Accesos y asistencia
| Tabla | Propósito |
|---|---|
| `control_acceso` | Cada intento de entrada con RFID/QR: sede, hora de entrada y salida, resultado y motivo de rechazo. |
| `registro_asistencias` | Una fila por cada acceso permitido; es el historial de asistencia. |

### Ventas, pagos y facturación
| Tabla | Propósito |
|---|---|
| `ventas` | Encabezado de cada venta: quién paga (un usuario **o** una empresa) y total sin IVA. |
| `detalles_venta` | Qué se vende: membresía, reserva, servicio o penalización (exactamente uno por línea), con el precio congelado. |
| `metodos_pago` | Efectivo, Tarjeta, Transferencia y PayPal. |
| `pagos` | Pagos de una venta (admite varios: pagos parciales y métodos distintos) con su estado. |
| `facturas` | Documento fiscal de una venta (1:1): subtotal, IVA, recargo, total, saldo pendiente, vencimiento y anulación. |
| `reembolsos` | Devoluciones de dinero por cancelación de reservas. |

### Reportes y auditoría
| Tabla | Propósito |
|---|---|
| `reportes_financieros` | Resumen de ingresos por periodo (lo genera un evento cada mes). |
| `notificaciones` | Recordatorios, alertas y reportes dirigidos a usuarios, administración, recepción, contabilidad o gerentes. |
| `log_auditoria` | Registro de cambios de membresía, cancelaciones, pagos anulados, accesos rechazados y salidas automáticas. |

### Cómo interactúan

- Una **persona** puede ser **usuario** del coworking y **empleado** de una o varias **empresas**.
- El usuario compra **membresías** (cada compra es una **suscripción**), hace **reservas** de **espacios** y consume **servicios**.
- Todo lo que se cobra se registra como **detalle** de una **venta**. La venta tiene uno o varios **pagos** y una **factura**. Una empresa recibe una factura consolidada con las membresías corporativas, reservas y servicios de sus empleados.
- En la puerta, cada lectura RFID/QR crea un registro en **control_acceso**. Si se permite, se registra la **asistencia**; si se rechaza, queda en el **log**.
- Las **reglas de negocio** se aplican con restricciones `CHECK` (por ejemplo, una venta tiene exactamente un comprador y cada detalle exactamente un concepto), triggers y procedimientos.

### Datos de prueba

| Tabla | Filas | Tabla | Filas |
|---|--:|---|--:|
| personas / usuarios | 60 | ventas | 535 |
| empresas | 5 | detalles_venta | 2.279 |
| espacios | 16 | pagos | 524 |
| suscripciones | 465 | facturas | 531 |
| reservas | 529 | control_acceso | 3.005 |
| servicio_usuario | 1.349 | registro_asistencias | 2.923 |

Los montos están en dólares (por ejemplo, membresía mensual $180, sala de reuniones $30/hora) para que los umbrales del enunciado ($200, $500, $1.000) sean significativos.

---

## 6. Ejemplos de consultas

Resultados con la fecha de referencia (`SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');`).

**Básica — Consulta 05: usuarios por tipo de membresía activa**

```sql
SELECT m.tipo_membresia, COUNT(DISTINCT s.id_usuario) AS usuarios
FROM membresias m
LEFT JOIN suscripciones s ON s.id_membresia = m.id_membresia AND s.estado = 'ACTIVA'
GROUP BY m.tipo_membresia
ORDER BY usuarios DESC;
```

| tipo_membresia | usuarios |
|---|--:|
| CORPORATIVA | 29 |
| MENSUAL | 9 |
| PREMIUM | 5 |
| DIARIA | 0 |

**Básica — Consulta 58: ingresos por método de pago**

```sql
SELECT mp.nombre AS metodo_pago, COUNT(p.id_pago) AS pagos, COALESCE(SUM(p.monto), 0) AS total_recaudado
FROM metodos_pago mp
LEFT JOIN pagos p ON p.id_metodo_pago = mp.id_metodo_pago AND p.estado = 'PAGADO'
GROUP BY mp.id_metodo_pago, mp.nombre
ORDER BY total_recaudado DESC;
```

Transferencia encabeza el recaudo (238 pagos, $114.396,48) porque es el método de las facturas corporativas.

**Intermedia — Consulta 34: reservas que se solapan**

Une la tabla `reservas` consigo misma para encontrar pares del mismo espacio cuyos horarios se cruzan (`b.inicio < a.fin AND b.fin > a.inicio`). Devuelve los dos pares incluidos a propósito en los datos, anteriores al trigger que hoy lo impide.

**Avanzada — Consulta 88: ocupación global por mes (CTE recursivo)**

Genera un calendario día por día con un `WITH RECURSIVE`, lo cruza con `horarios_atencion` para calcular las horas que cada espacio estuvo disponible, y lo compara con las horas reservadas. Responde qué porcentaje real de la capacidad del coworking se usó cada mes.

**Avanzada — Consulta 99: ingresos acumulados con función de ventana**

```sql
SELECT t.mes, t.ingresos,
       SUM(t.ingresos) OVER (ORDER BY t.mes) AS ingresos_acumulados
FROM (SELECT DATE_FORMAT(f.fecha_emision, '%Y-%m') AS mes, SUM(f.subtotal) AS ingresos
        FROM facturas f
       WHERE f.estado <> 'ANULADA'
       GROUP BY DATE_FORMAT(f.fecha_emision, '%Y-%m')) AS t
ORDER BY t.mes;
```

**Avanzada — Consulta 85: empresas que generan más del 20 % de los ingresos**

Con subconsultas correlacionadas suma, para cada empresa, sus facturas consolidadas y las compras individuales de sus empleados, y lo compara con el total. Resultado: Innovatek S.A.S.

---

## 7. Procedimientos, funciones, triggers y eventos

### 7.1 Funciones (`sql/03_funciones/01_funciones.sql`)

| Módulo | Función | Devuelve |
|---|---|---|
| Membresías | `fn_membresia_activa(usuario)` | TRUE si tiene una membresía activa vigente hoy |
| | `fn_dias_restantes_membresia(usuario)` | Días de vigencia restantes (incluye membresías acumuladas) |
| | `fn_tipo_membresia(usuario)` | Tipo de la membresía actual |
| | `fn_renovaciones_membresia(usuario)` | Número de renovaciones |
| | `fn_estado_membresia(usuario)` | ACTIVA, SUSPENDIDA, VENCIDA, PENDIENTE o SIN_MEMBRESIA |
| Reservas | `fn_total_reservas(usuario)` | Total de reservas del usuario |
| | `fn_horas_reservadas(usuario, mes, año)` | Horas reservadas en el periodo |
| | `fn_espacio_mas_reservado()` | ID del espacio con más reservas |
| | `fn_reservas_activas(usuario)` | Reservas pendientes o confirmadas aún vigentes |
| | `fn_duracion_promedio_reservas(espacio)` | Duración promedio en horas |
| Pagos | `fn_total_pagado(usuario)` | Total pagado (con IVA) |
| | `fn_ingresos_por_mes(mes, año)` | Ingresos sin IVA del mes |
| | `fn_ingresos_por_membresias()` | Ingresos por membresías |
| | `fn_ingresos_por_reservas()` | Ingresos por reservas |
| | `fn_ingresos_por_empresa(empresa)` | Ingresos facturados a una empresa |
| Accesos | `fn_total_asistencias(usuario)` | Total de asistencias |
| | `fn_asistencias_mes(usuario, mes, año)` | Asistencias en el mes |
| | `fn_top_usuario_asistencias()` | Usuario con más asistencias |
| | `fn_ultima_asistencia(usuario)` | Fecha y hora de la última asistencia |
| | `fn_promedio_asistencias()` | Promedio de asistencias por usuario |

```sql
SELECT fn_membresia_activa(3), fn_tipo_membresia(3), fn_dias_restantes_membresia(3);
-- 1 | CORPORATIVA | 31   (con la fecha de referencia)
```

### 7.2 Procedimientos almacenados (`sql/04_procedimientos/01_procedimientos.sql`)

| Módulo | Procedimiento | Qué hace |
|---|---|---|
| Membresías | `sp_registrar_membresia(usuario, tipo, inicio, OUT id)` | Registra una membresía PENDIENTE (acumulable si `inicio` es NULL) y su venta. |
| | `sp_renovar_membresia(usuario, OUT id)` | Renueva con el mismo tipo, empezando donde termina la actual. No renueva si está suspendida. |
| | `sp_actualizar_membresias_vencidas(OUT n)` | Pasa a VENCIDA las activas cuya fecha de fin ya pasó. |
| | `sp_suspender_membresias_morosas(dias, OUT n)` | Suspende membresías de usuarios (o empleados de empresas) con facturas vencidas hace más de X días. |
| Reservas | `sp_verificar_disponibilidad(espacio, inicio, fin, OUT ok, OUT motivo)` | Comprueba estado del espacio, horario de la sede y solapamiento. |
| | `sp_crear_reserva(usuario, espacio, inicio, fin, personas, OUT id)` | Crea la reserva PENDIENTE y su venta; si el usuario es corporativo, la confirma con crédito de la empresa. |
| | `sp_confirmar_reserva_pago(reserva, metodo, OUT pago)` | Registra el pago; los triggers crean la factura y confirman la reserva. |
| | `sp_cancelar_reserva(reserva, porcentaje, OUT reembolso)` | Cancela y reembolsa (100 % con 48 h o más, 50 % con menos, 0 % si ya empezó). |
| | `sp_liberar_reservas_no_confirmadas(horas, OUT n)` | Cancela (con cursor) las reservas pendientes de más de X horas. |
| Pagos | `sp_generar_factura_membresia(suscripcion, OUT factura)` | Crea la factura de una membresía (sin duplicar). |
| | `sp_generar_factura_empresa(empresa, año, mes, OUT factura)` | Factura consolidada con membresías, reservas, penalizaciones y servicios de los empleados. |
| | `sp_aplicar_recargos(dias, porcentaje, OUT n)` | Recargo a facturas vencidas hace más de X días. |
| | `sp_bloquear_servicios_morosos(dias, OUT bloq, OUT desbloq)` | Bloquea servicios a morosos y desbloquea a quienes ya pagaron. |
| Accesos | `sp_registrar_entrada(codigo, sede, metodo, OUT id, OUT resultado, OUT motivo)` | Registra la lectura RFID/QR, valida y cierra la entrada anterior si quedó abierta. |
| | `sp_registrar_salida(codigo, OUT id)` | Marca la hora de salida. |
| | `sp_reporte_diario_asistencias(fecha)` | Ingresos, usuarios únicos, rechazos, permanencia, hora pico, y detalle por hora y sede. |
| | `sp_marcar_no_show(porcentaje, OUT marcadas, OUT penalizadas)` | Marca NO_SHOW y genera la penalización (con cursor). |
| Corporativos | `sp_registrar_lote_empleados(empresa, json, inicio, OUT n)` | Registra varios empleados desde un arreglo JSON con membresía corporativa. |
| | `sp_cancelar_reservas_futuras(usuario, OUT n)` | Cancela (con cursor) las reservas futuras al eliminar la membresía. |
| | `sp_reporte_ingresos_mensuales(año)` | Ingresos y recaudo por mes con acumulados (CTE recursivo + `OVER`). |

```sql
-- Reservar la Sala Andes y pagarla con tarjeta
CALL sp_crear_reserva(56, 5, '2026-10-20 09:00', '2026-10-20 11:00', 4, @reserva);
CALL sp_confirmar_reserva_pago(@reserva, 2, @pago);

-- Entrada con el código del usuario 3 en la Sede Centro
CALL sp_registrar_entrada('RFID-181860', 1, 'RFID', @id, @resultado, @motivo);
```

Los procedimientos no abren transacciones propias, para poder llamarse entre sí (por ejemplo, `sp_cancelar_reservas_futuras` llama a `sp_cancelar_reserva`) y desde pruebas con `ROLLBACK`. Validan los datos antes de escribir; para atomicidad total, llámalos dentro de `START TRANSACTION ... COMMIT`.

### 7.3 Triggers (`sql/05_triggers/01_triggers.sql`)

20 triggers lógicos (25 físicos, porque algunos se implementan para `INSERT` y para `UPDATE`). El orden entre triggers del mismo evento se fija con `FOLLOWS`.

| Módulo | Trigger | Regla |
|---|---|---|
| Membresías | `trg_suscripciones_bi_fecha_vencimiento` | Calcula la fecha de vencimiento según el tipo. |
| | `trg_pagos_ai/au_activar_membresia` | Pago exitoso → membresía ACTIVA. |
| | `trg_facturas_au_suspender_membresia` | Factura vencida sin pagar → membresía SUSPENDIDA. |
| | `trg_suscripciones_au_log_cambio_tipo` | Log del cambio de tipo de membresía. |
| | `trg_suscripciones_bd_bloquear_eliminacion` | Impide borrar una membresía con reservas confirmadas vigentes. |
| Reservas | `trg_reservas_bi_validar_duplicada` | Rechaza reservas solapadas en el mismo espacio. |
| | `trg_reservas_bi_estado_pendiente` | Toda reserva nueva nace PENDIENTE. |
| | `trg_pagos_ai/au_confirmar_reserva` | Pago de la reserva → CONFIRMADA. |
| | `trg_suscripciones_ad_cancelar_reservas` | Al eliminar la membresía, cancela las reservas futuras. |
| | `trg_reservas_au_log_cancelacion` | Log de cada cancelación. |
| Pagos | `trg_pagos_ai_crear_factura` | Crea la factura al registrar el primer pago. |
| | `trg_pagos_ai/au_actualizar_saldo` | Recalcula el saldo (pagos parciales y anulaciones). |
| | `trg_pagos_ai/au_factura_pagada` | Saldo en 0 → factura PAGADA. |
| | `trg_pagos_bd_bloquear_eliminacion` | Impide borrar un pago con factura. |
| | `trg_pagos_ai/au_log_anulacion` | Log de pagos anulados. |
| Accesos | `trg_control_acceso_bi_validar_acceso` | Valida horario, membresía activa o reserva; si no cumple, el intento queda DENEGADO con su motivo. |
| | `trg_control_acceso_bi_salida_automatica` | Detecta reingreso sin salida y lo registra. |
| | `trg_control_acceso_ai_registrar_asistencia` | Acceso permitido → asistencia. |
| | `trg_control_acceso_ai_ultimo_acceso` | Actualiza el último acceso del usuario. |
| | `trg_control_acceso_ai_log_rechazo` | Log de cada intento rechazado. |

Ejemplo: registrar un pago basta para que el sistema cree la factura, actualice el saldo, la marque pagada y confirme la reserva o active la membresía:

```sql
INSERT INTO pagos (id_venta, id_metodo_pago, monto, estado) VALUES (@venta, 2, 71.40, 'PAGADO');
```

### 7.4 Eventos (`sql/06_eventos/01_eventos.sql`)

Los envíos (recordatorios, reportes y alertas) se registran en la tabla `notificaciones`.

| Módulo | Evento | Frecuencia | Qué hace |
|---|---|---|---|
| Membresías | `evt_membresias_vencidas` | Diario | Marca vencidas (`CALL sp_actualizar_membresias_vencidas`). |
| | `evt_recordatorio_renovacion` | Diario | Aviso 5 días antes de vencer. |
| | `evt_suspender_sin_pago` | Diario | Suspende membresías pendientes de pago por 30 días. |
| | `evt_reporte_nuevas_membresias` | Semanal | Reporte al administrador. |
| | `evt_notificar_suspendidas` | Diario | Aviso a recepción. |
| Reservas | `evt_cancelar_reservas_pendientes` | Cada 5 min | Cancela pendientes de más de 2 h (`CALL sp_liberar_reservas_no_confirmadas`). |
| | `evt_recordatorio_reserva` | Cada 5 min | Aviso 1 hora antes, sin duplicados. |
| | `evt_eliminar_reservas_no_asistidas` | Diario | Borra NO_SHOW de hace más de 7 días sin dependencias. |
| | `evt_reporte_ocupacion_semanal` | Semanal | Horas ocupadas de la semana. |
| | `evt_liberar_reservas_no_iniciadas` | Cada 5 min | Libera reservas que no empezaron en 15 min. |
| Pagos | `evt_recordatorio_pago` | Cada 3 días | Aviso al usuario o al gerente de la empresa. |
| | `evt_bloquear_servicios` | Diario | `CALL sp_bloquear_servicios_morosos(10)`. |
| | `evt_resumen_facturacion_mensual` | Mensual | Inserta el reporte en `reportes_financieros`. |
| | `evt_recargo_facturas_vencidas` | Diario | `CALL sp_aplicar_recargos(15, 5)`. |
| | `evt_reporte_ingresos_contador` | Fin de mes | Reporte al contador. |
| Accesos | `evt_eliminar_accesos_antiguos` | Diario | Borra accesos de más de 1 año. |
| | `evt_reporte_asistencias_diario` | Diario | Reporte al administrador. |
| | `evt_reporte_usuarios_inactivos` | Semanal | Usuarios sin accesos en 7 días. |
| | `evt_alerta_accesos_fuera_horario` | Diario | Alerta de accesos fuera de horario. |
| | `evt_reporte_top_usuarios` | Mensual | Top 10 de usuarios más frecuentes. |

---

## 8. Roles de usuario y permisos

| Rol | Puede |
|---|---|
| `rol_administrador` | Todo sobre la base de datos (con `GRANT OPTION`). |
| `rol_recepcionista` | Registrar personas y usuarios, consultar la operación, asignar y renovar membresías, gestionar reservas y registrar entradas y salidas (por procedimientos). No ve información financiera. |
| `rol_usuario` | Consultar el catálogo, reservar y cancelar **sus** reservas, y ver **su** perfil, membresías, asistencias y facturas (vistas filtradas por la cuenta conectada). |
| `rol_gerente_corporativo` | Lo mismo que Usuario, más ver y registrar empleados de **su** empresa y consultar su facturación consolidada. |
| `rol_contador` | Consultar ventas, pagos, facturas y reembolsos, anular facturas, aplicar recargos, generar facturas y reportes de ingresos. No ve contraseñas ni datos de acceso. |

**Crear un usuario y asignarle un rol:**

```sql
CREATE USER 'jperez'@'localhost' IDENTIFIED BY 'ClaveSegura#1';
GRANT 'rol_recepcionista' TO 'jperez'@'localhost';
SET DEFAULT ROLE ALL TO 'jperez'@'localhost';
```

Para los roles Usuario y Gerente, la cuenta debe llamarse igual que `usuarios.nombre_usuario`. `03_usuarios_ejemplo.sql` crea una cuenta por rol (por ejemplo, `nflorez56` para el usuario 56 y `vpabon1` para el gerente de Innovatek).

La matriz completa de permisos, las vistas de seguridad y las pruebas por cuenta están en [`docs/roles_permisos.md`](docs/roles_permisos.md).

---

## 9. Contribuciones

| Integrante | Aporte |
|---|---|
| Jhorman Fabian Peñaloza Sierra | Procedimientos almacenados (20) y sus pruebas; integración y revisión del repositorio |
| _[Nombre del integrante]_ | Modelo lógico y DDL |
| _[Nombre del integrante]_ | Datos iniciales (DML) |
| _[Nombre del integrante]_ | Consultas de usuarios y membresías (01-20) |
| _[Nombre del integrante]_ | Consultas de espacios y reservas (21-40) |
| _[Nombre del integrante]_ | Consultas de pagos y facturación (41-60) |
| _[Nombre del integrante]_ | Consultas de accesos y asistencias (61-80) |
| _[Nombre del integrante]_ | Consultas avanzadas (81-100) |
| _[Nombre del integrante]_ | Funciones (20) |
| _[Nombre del integrante]_ | Triggers (20) y sus pruebas |
| _[Nombre del integrante]_ | Eventos (20) |
| _[Nombre del integrante]_ | Roles, permisos y usuarios |

---

## 10. Licencia y contacto

Proyecto académico con fines educativos. Puede reutilizarse citando a sus autores.

Para preguntas o problemas con la implementación, abre un *issue* en este repositorio o escribe a:

- Jhorman Fabian Peñaloza Sierra — _[correo o usuario de GitHub]_
- _[Integrante]_ — _[correo o usuario de GitHub]_
