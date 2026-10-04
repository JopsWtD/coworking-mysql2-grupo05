/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Espacios y Reservas
Archivo: 02_espacios_reservas.sql
Descripción:
  Consultas 21 a 40 del módulo.
  Criterios usados:
    * Reserva activa   = PENDIENTE o CONFIRMADA.
    * Reserva ocupada  = CONFIRMADA, FINALIZADA o NO_SHOW (el espacio quedó
                         bloqueado aunque no se usara); las CANCELADAS no cuentan.
    * Horas disponibles de un espacio = horas de atención de su sede
                         (tabla horarios_atencion) en los días del periodo.
Requisitos:
  Ejecutar previamente DDL, DML y funciones (Q38 usa fn_duracion_promedio_reservas).
  Los datos de prueba tienen como fecha de referencia el 2026-10-01; para
  reproducir los resultados documentados ejecutar antes:
    SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');
*/
USE coworking_grupo5;

-- =========================================
-- CONSULTA 21
-- Listar todos los espacios disponibles con su capacidad.
-- =========================================
SELECT e.id_espacio,
       s.nombre_sede,
       e.nombre,
       e.tipo_espacio,
       e.capacidad,
       e.precio_hora
FROM espacios e
JOIN sedes_coworking s ON s.id_sede_coworking = e.id_sede_coworking
WHERE e.estado = 'DISPONIBLE'
ORDER BY s.nombre_sede, e.tipo_espacio, e.nombre;

-- =========================================
-- CONSULTA 22
-- Listar reservas activas en el día actual.
-- =========================================
SELECT r.id_reserva,
       e.nombre                           AS espacio,
       u.nombre_usuario,
       TIME(r.fecha_inicio)               AS hora_inicio,
       TIME(r.fecha_fin)                  AS hora_fin,
       r.cantidad_personas,
       r.estado
FROM reservas r
JOIN espacios e ON e.id_espacio = r.id_espacio
JOIN usuarios u ON u.id_usuario = r.id_usuario
WHERE DATE(r.fecha_inicio) = CURDATE()
  AND r.estado IN ('PENDIENTE', 'CONFIRMADA')
ORDER BY r.fecha_inicio;

-- =========================================
-- CONSULTA 23
-- Mostrar reservas canceladas en el último mes.
-- La fecha de cancelación se toma del log de auditoría; si no existe,
-- se usa la fecha de la reserva.
-- =========================================
SELECT r.id_reserva,
       u.nombre_usuario,
       e.nombre                                      AS espacio,
       r.fecha_inicio,
       COALESCE(MAX(l.fecha_hora), r.fecha_inicio)   AS fecha_cancelacion
FROM reservas r
JOIN usuarios u ON u.id_usuario = r.id_usuario
JOIN espacios e ON e.id_espacio = r.id_espacio
LEFT JOIN log_auditoria l
       ON l.tabla_afectada = 'reservas'
      AND l.id_registro    = r.id_reserva
      AND l.accion         = 'CANCELACION'
WHERE r.estado = 'CANCELADA'
GROUP BY r.id_reserva, u.nombre_usuario, e.nombre, r.fecha_inicio
HAVING fecha_cancelacion >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
   AND fecha_cancelacion <  CURDATE() + INTERVAL 1 DAY
ORDER BY fecha_cancelacion DESC;

-- =========================================
-- CONSULTA 24
-- Listar reservas de salas de reuniones en horario pico (9 am – 11 am).
-- Se incluyen las que se cruzan, aunque sea en parte, con esa franja.
-- =========================================
SELECT r.id_reserva,
       e.nombre                AS sala,
       DATE(r.fecha_inicio)    AS fecha,
       TIME(r.fecha_inicio)    AS hora_inicio,
       TIME(r.fecha_fin)       AS hora_fin,
       r.estado
FROM reservas r
JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE e.tipo_espacio = 'SALA_REUNIONES'
  AND r.estado <> 'CANCELADA'
  AND TIME(r.fecha_inicio) < '11:00:00'
  AND TIME(r.fecha_fin)    > '09:00:00'
ORDER BY r.fecha_inicio;

-- =========================================
-- CONSULTA 25
-- Contar cuántas reservas se hacen por cada tipo de espacio.
-- =========================================
SELECT e.tipo_espacio,
       COUNT(r.id_reserva)                  AS total_reservas,
       SUM(r.estado <> 'CANCELADA')         AS reservas_efectivas,
       SUM(r.estado = 'CANCELADA')          AS canceladas
FROM espacios e
LEFT JOIN reservas r ON r.id_espacio = e.id_espacio
GROUP BY e.tipo_espacio
ORDER BY total_reservas DESC;

-- =========================================
-- CONSULTA 26
-- Mostrar el espacio más reservado del último mes (incluye empates).
-- =========================================
SELECT id_espacio, nombre, tipo_espacio, reservas
FROM (
    SELECT e.id_espacio, e.nombre, e.tipo_espacio,
           COUNT(*) AS reservas,
           RANK() OVER (ORDER BY COUNT(*) DESC) AS posicion
    FROM reservas r
    JOIN espacios e ON e.id_espacio = r.id_espacio
    WHERE r.estado <> 'CANCELADA'
      AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
      AND r.fecha_inicio <  CURDATE()
    GROUP BY e.id_espacio, e.nombre, e.tipo_espacio
) t
WHERE posicion = 1;

-- =========================================
-- CONSULTA 27
-- Listar usuarios que más han reservado salas privadas (oficinas privadas).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*)                                                            AS reservas_oficina,
       ROUND(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 1) AS horas
FROM reservas r
JOIN espacios e ON e.id_espacio = r.id_espacio
JOIN usuarios u ON u.id_usuario = r.id_usuario
WHERE e.tipo_espacio = 'OFICINA_PRIVADA'
  AND r.estado <> 'CANCELADA'
GROUP BY u.id_usuario, u.nombre_usuario
ORDER BY reservas_oficina DESC, horas DESC
LIMIT 10;

-- =========================================
-- CONSULTA 28
-- Mostrar reservas que exceden la capacidad máxima del espacio.
-- =========================================
SELECT r.id_reserva,
       e.nombre                            AS espacio,
       e.capacidad,
       r.cantidad_personas,
       r.cantidad_personas - e.capacidad   AS exceso,
       r.fecha_inicio,
       r.estado
FROM reservas r
JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE r.cantidad_personas > e.capacidad
ORDER BY exceso DESC;

-- =========================================
-- CONSULTA 29
-- Listar espacios que no se han reservado en la última semana.
-- =========================================
SELECT e.id_espacio, e.nombre, e.tipo_espacio, e.estado
FROM espacios e
WHERE NOT EXISTS (SELECT 1
                    FROM reservas r
                   WHERE r.id_espacio   = e.id_espacio
                     AND r.estado      <> 'CANCELADA'
                     AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                     AND r.fecha_inicio <  CURDATE())
ORDER BY e.id_espacio;

-- =========================================
-- CONSULTA 30
-- Calcular la tasa de ocupación promedio de cada espacio
-- (últimos 90 días): horas ocupadas / horas de atención de la sede.
-- =========================================
WITH RECURSIVE dias AS (
    SELECT DATE_SUB(CURDATE(), INTERVAL 90 DAY) AS dia
    UNION ALL
    SELECT dia + INTERVAL 1 DAY FROM dias WHERE dia < DATE_SUB(CURDATE(), INTERVAL 1 DAY)
),
disponible AS (
    SELECT e.id_espacio,
           SUM(TIME_TO_SEC(TIMEDIFF(h.hora_fin, h.hora_inicio))) / 3600 AS horas_disponibles
    FROM espacios e
    JOIN dias d
    JOIN horarios_atencion h
      ON h.id_sede_coworking = e.id_sede_coworking
     AND h.dia_semana = ELT(WEEKDAY(d.dia) + 1, 'LUNES','MARTES','MIERCOLES',
                            'JUEVES','VIERNES','SABADO','DOMINGO')
    GROUP BY e.id_espacio
),
ocupado AS (
    SELECT id_espacio,
           SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / 60 AS horas_ocupadas
    FROM reservas
    WHERE estado IN ('CONFIRMADA', 'FINALIZADA', 'NO_SHOW')
      AND fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
      AND fecha_inicio <  CURDATE()
    GROUP BY id_espacio
)
SELECT e.id_espacio, e.nombre, e.tipo_espacio,
       ROUND(COALESCE(o.horas_ocupadas, 0), 1)                                AS horas_ocupadas,
       ROUND(d.horas_disponibles, 1)                                          AS horas_disponibles,
       ROUND(COALESCE(o.horas_ocupadas, 0) * 100 / d.horas_disponibles, 2)    AS tasa_ocupacion_pct
FROM espacios e
JOIN disponible d    ON d.id_espacio = e.id_espacio
LEFT JOIN ocupado o  ON o.id_espacio = e.id_espacio
ORDER BY tasa_ocupacion_pct DESC;

-- =========================================
-- CONSULTA 31
-- Mostrar reservas de más de 8 horas.
-- =========================================
SELECT r.id_reserva,
       u.nombre_usuario,
       e.nombre                                                      AS espacio,
       r.fecha_inicio,
       r.fecha_fin,
       ROUND(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin) / 60, 1) AS horas,
       r.estado
FROM reservas r
JOIN usuarios u ON u.id_usuario = r.id_usuario
JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin) > 8 * 60
ORDER BY horas DESC, r.fecha_inicio;

-- =========================================
-- CONSULTA 32
-- Identificar usuarios con más de 20 reservas en total.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*) AS total_reservas
FROM reservas r
JOIN usuarios u ON u.id_usuario = r.id_usuario
GROUP BY u.id_usuario, u.nombre_usuario
HAVING COUNT(*) > 20
ORDER BY total_reservas DESC;

-- =========================================
-- CONSULTA 33
-- Mostrar reservas realizadas por empresas con más de 10 empleados
-- (reservas hechas por los empleados de esas empresas).
-- =========================================
SELECT emp.razon_social,
       emp.empleados,
       r.id_reserva,
       u.nombre_usuario,
       e.nombre          AS espacio,
       r.fecha_inicio,
       r.estado
FROM (SELECT em.id_empresa, em.razon_social, COUNT(*) AS empleados
        FROM empresas em
        JOIN empleados_empresa ee ON ee.id_empresa = em.id_empresa
       GROUP BY em.id_empresa, em.razon_social
      HAVING COUNT(*) > 10) emp
JOIN empleados_empresa ee ON ee.id_empresa = emp.id_empresa
JOIN usuarios u           ON u.id_persona  = ee.id_persona
JOIN reservas r           ON r.id_usuario  = u.id_usuario
JOIN espacios e           ON e.id_espacio  = r.id_espacio
ORDER BY emp.razon_social, r.fecha_inicio;

-- =========================================
-- CONSULTA 34
-- Listar reservas que se solapan en horario (mismo espacio, no canceladas).
-- =========================================
SELECT e.nombre          AS espacio,
       a.id_reserva      AS reserva_1,
       a.fecha_inicio    AS inicio_1,
       a.fecha_fin       AS fin_1,
       b.id_reserva      AS reserva_2,
       b.fecha_inicio    AS inicio_2,
       b.fecha_fin       AS fin_2
FROM reservas a
JOIN reservas b ON b.id_espacio   = a.id_espacio
               AND b.id_reserva   > a.id_reserva
               AND b.fecha_inicio < a.fecha_fin
               AND b.fecha_fin    > a.fecha_inicio
JOIN espacios e ON e.id_espacio = a.id_espacio
WHERE a.estado <> 'CANCELADA'
  AND b.estado <> 'CANCELADA'
ORDER BY a.fecha_inicio;

-- =========================================
-- CONSULTA 35
-- Listar reservas de fin de semana (sábado o domingo).
-- =========================================
SELECT r.id_reserva,
       CASE DAYOFWEEK(r.fecha_inicio) WHEN 1 THEN 'DOMINGO' ELSE 'SABADO' END AS dia,
       r.fecha_inicio,
       r.fecha_fin,
       e.nombre AS espacio,
       u.nombre_usuario,
       r.estado
FROM reservas r
JOIN espacios e ON e.id_espacio = r.id_espacio
JOIN usuarios u ON u.id_usuario = r.id_usuario
WHERE DAYOFWEEK(r.fecha_inicio) IN (1, 7)
ORDER BY r.fecha_inicio;

-- =========================================
-- CONSULTA 36
-- Mostrar el porcentaje de ocupación por cada tipo de espacio
-- (últimos 90 días, horas ocupadas / horas de atención).
-- =========================================
WITH RECURSIVE dias AS (
    SELECT DATE_SUB(CURDATE(), INTERVAL 90 DAY) AS dia
    UNION ALL
    SELECT dia + INTERVAL 1 DAY FROM dias WHERE dia < DATE_SUB(CURDATE(), INTERVAL 1 DAY)
),
disponible AS (
    SELECT e.tipo_espacio,
           SUM(TIME_TO_SEC(TIMEDIFF(h.hora_fin, h.hora_inicio))) / 3600 AS horas_disponibles
    FROM espacios e
    JOIN dias d
    JOIN horarios_atencion h
      ON h.id_sede_coworking = e.id_sede_coworking
     AND h.dia_semana = ELT(WEEKDAY(d.dia) + 1, 'LUNES','MARTES','MIERCOLES',
                            'JUEVES','VIERNES','SABADO','DOMINGO')
    GROUP BY e.tipo_espacio
),
ocupado AS (
    SELECT e.tipo_espacio,
           SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60 AS horas_ocupadas
    FROM reservas r
    JOIN espacios e ON e.id_espacio = r.id_espacio
    WHERE r.estado IN ('CONFIRMADA', 'FINALIZADA', 'NO_SHOW')
      AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
      AND r.fecha_inicio <  CURDATE()
    GROUP BY e.tipo_espacio
)
SELECT d.tipo_espacio,
       ROUND(COALESCE(o.horas_ocupadas, 0), 1)                             AS horas_ocupadas,
       ROUND(d.horas_disponibles, 1)                                       AS horas_disponibles,
       ROUND(COALESCE(o.horas_ocupadas, 0) * 100 / d.horas_disponibles, 2) AS ocupacion_pct
FROM disponible d
LEFT JOIN ocupado o ON o.tipo_espacio = d.tipo_espacio
ORDER BY ocupacion_pct DESC;

-- =========================================
-- CONSULTA 37
-- Mostrar la duración promedio de reservas por tipo de espacio (en horas).
-- =========================================
SELECT e.tipo_espacio,
       COUNT(*)                                                               AS reservas,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 2) AS duracion_promedio_horas
FROM reservas r
JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE r.estado <> 'CANCELADA'
GROUP BY e.tipo_espacio
ORDER BY duracion_promedio_horas DESC;

-- =========================================
-- CONSULTA 38
-- Mostrar reservas con servicios adicionales incluidos.
-- =========================================
SELECT r.id_reserva,
       u.nombre_usuario,
       e.nombre                                                    AS espacio,
       r.fecha_inicio,
       GROUP_CONCAT(DISTINCT sv.nombre ORDER BY sv.nombre SEPARATOR ', ') AS servicios,
       SUM(su.cantidad * sv.precio)                                AS valor_servicios
FROM reservas r
JOIN servicio_usuario su ON su.id_reserva  = r.id_reserva
JOIN servicios sv        ON sv.id_servicio = su.id_servicio
JOIN usuarios u          ON u.id_usuario   = r.id_usuario
JOIN espacios e          ON e.id_espacio   = r.id_espacio
GROUP BY r.id_reserva, u.nombre_usuario, e.nombre, r.fecha_inicio
ORDER BY r.fecha_inicio DESC;

-- =========================================
-- CONSULTA 39
-- Listar usuarios que reservaron sala de eventos en los últimos 6 meses.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*)              AS reservas_eventos,
       MAX(r.fecha_inicio)   AS ultima_reserva
FROM reservas r
JOIN espacios e ON e.id_espacio = r.id_espacio
JOIN usuarios u ON u.id_usuario = r.id_usuario
WHERE e.tipo_espacio = 'SALA_EVENTOS'
  AND r.estado <> 'CANCELADA'
  AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
GROUP BY u.id_usuario, u.nombre_usuario
ORDER BY ultima_reserva DESC;

-- =========================================
-- CONSULTA 40
-- Identificar reservas realizadas y nunca asistidas: las marcadas
-- NO_SHOW y las CONFIRMADAS que ya terminaron sin ninguna asistencia
-- asociada (aún no procesadas por sp_marcar_no_show).
-- =========================================
SELECT r.id_reserva,
       u.nombre_usuario,
       e.nombre           AS espacio,
       r.fecha_inicio,
       r.estado
FROM reservas r
JOIN usuarios u ON u.id_usuario = r.id_usuario
JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE r.estado IN ('CONFIRMADA', 'NO_SHOW')
  AND r.fecha_fin < NOW()
  AND NOT EXISTS (SELECT 1 FROM registro_asistencias a WHERE a.id_reserva = r.id_reserva)
ORDER BY r.fecha_inicio DESC;
