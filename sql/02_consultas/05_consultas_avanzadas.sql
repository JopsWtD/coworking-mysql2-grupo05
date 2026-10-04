/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Consultas avanzadas
Archivo: 05_consultas_avanzadas.sql
Descripción:
  Consultas 81 a 100: subconsultas (escalares, correlacionadas, IN, EXISTS,
  tablas derivadas), JOIN múltiples, CTE (incluido recursivo) y funciones
  de ventana (OVER).
  Criterio general: los ingresos se calculan SIN IVA y solo con facturas
  no anuladas.
Requisitos:
  Ejecutar previamente DDL y DML.
  Para reproducir los resultados documentados ejecutar antes:
    SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');
*/
USE coworking_grupo5;
-- =========================================
-- CONSULTA 81
-- Usuarios con el mayor gasto acumulado (subconsulta con SUM)
-- =========================================
SELECT u.id_usuario, u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
       (SELECT SUM(v.total)
        FROM ventas AS v
        JOIN facturas AS f ON f.id_venta = v.id_venta AND f.estado <> 'ANULADA'
        WHERE v.id_usuario = u.id_usuario) AS gasto_acumulado
FROM usuarios AS u
JOIN personas AS p ON p.id_persona = u.id_persona
WHERE EXISTS (SELECT 1 FROM ventas v2 WHERE v2.id_usuario = u.id_usuario)
ORDER BY gasto_acumulado DESC
LIMIT 10;

-- =========================================
-- CONSULTA 82
-- Espacios más ocupados (reservas confirmadas y asistencias reales)
-- =========================================
SELECT e.id_espacio, e.nombre, e.tipo_espacio,
       COUNT(DISTINCT r.id_reserva) AS reservas_confirmadas,
       COUNT(ra.id_registro) AS asistencias_reales
FROM espacios AS e
JOIN reservas AS r ON r.id_espacio = e.id_espacio
                   AND r.estado IN ('CONFIRMADA', 'FINALIZADA')
LEFT JOIN registro_asistencias AS ra ON ra.id_reserva = r.id_reserva
GROUP BY e.id_espacio, e.nombre, e.tipo_espacio
ORDER BY reservas_confirmadas DESC, asistencias_reales DESC
LIMIT 10;

-- =========================================
-- CONSULTA 83
-- Promedio de ingresos por usuario (subconsultas)
-- Primero se calcula el ingreso (sin IVA, facturas no anuladas) de cada
-- usuario en una subconsulta y luego se promedia; se muestra también
-- cuántos usuarios están por encima de ese promedio.
-- =========================================
SELECT COUNT(*)                         AS usuarios_con_compras,
       ROUND(AVG(t.ingresos), 2)        AS promedio_ingresos_por_usuario,
       (SELECT COUNT(*)
          FROM (SELECT v.id_usuario, SUM(v.total) AS ingresos
                  FROM ventas v
                  JOIN facturas f ON f.id_venta = v.id_venta AND f.estado <> 'ANULADA'
                 WHERE v.id_usuario IS NOT NULL
                 GROUP BY v.id_usuario) x
         WHERE x.ingresos > (SELECT AVG(y.ingresos)
                               FROM (SELECT SUM(v.total) AS ingresos
                                       FROM ventas v
                                       JOIN facturas f ON f.id_venta = v.id_venta AND f.estado <> 'ANULADA'
                                      WHERE v.id_usuario IS NOT NULL
                                      GROUP BY v.id_usuario) y)) AS usuarios_sobre_el_promedio
FROM (SELECT v.id_usuario, SUM(v.total) AS ingresos
        FROM ventas v
        JOIN facturas f ON f.id_venta = v.id_venta AND f.estado <> 'ANULADA'
       WHERE v.id_usuario IS NOT NULL
       GROUP BY v.id_usuario) AS t;

-- =========================================
-- CONSULTA 84
-- Usuarios con reservas activas y facturas pendientes.
-- =========================================
SELECT u.id_usuario, u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre
FROM usuarios AS u
JOIN personas AS p ON p.id_persona = u.id_persona
WHERE u.id_usuario IN (
        SELECT id_usuario
        FROM reservas
        WHERE estado IN ('PENDIENTE', 'CONFIRMADA')
          AND fecha_fin >= NOW())
AND u.id_usuario IN (
        SELECT v.id_usuario
        FROM ventas AS v
        JOIN facturas AS f ON f.id_venta = v.id_venta
        WHERE f.estado = 'PENDIENTE');

-- =========================================
-- CONSULTA 85
-- Empresas cuyos empleados generan más del 20% de los ingresos totales.
-- Ingresos de la empresa = ventas facturadas a nombre de la empresa
-- (factura consolidada) + ventas individuales de sus empleados.
-- Se usan valores sin IVA de facturas no anuladas.
-- =========================================
SELECT t.id_empresa, t.razon_social, t.ingresos_empresa,
       ROUND(t.ingresos_empresa * 100 / t.ingresos_totales, 2) AS porcentaje
FROM (
    SELECT e.id_empresa, e.razon_social,
           (SELECT SUM(v.total)
              FROM ventas v
              JOIN facturas f ON f.id_venta = v.id_venta AND f.estado <> 'ANULADA'
             WHERE v.id_empresa = e.id_empresa
                OR v.id_usuario IN (SELECT u.id_usuario
                                      FROM empleados_empresa ee
                                      JOIN usuarios u ON u.id_persona = ee.id_persona
                                     WHERE ee.id_empresa = e.id_empresa)) AS ingresos_empresa,
           (SELECT SUM(v.total)
              FROM ventas v
              JOIN facturas f ON f.id_venta = v.id_venta AND f.estado <> 'ANULADA') AS ingresos_totales
    FROM empresas AS e
) AS t
WHERE t.ingresos_empresa > 0.20 * t.ingresos_totales
ORDER BY porcentaje DESC;

-- =========================================
-- CONSULTA 86
-- Top 5 de usuarios que más usan servicios adicionales.
-- =========================================
SELECT u.id_usuario, u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
       COUNT(*) AS usos_servicios,
       SUM(su.cantidad) AS unidades
FROM servicio_usuario AS su
JOIN usuarios AS u ON u.id_usuario = su.id_usuario
JOIN personas AS p ON p.id_persona = u.id_persona
GROUP BY u.id_usuario, u.nombre_usuario, p.primer_nombre, p.primer_apellido
ORDER BY usos_servicios DESC, unidades DESC
LIMIT 5;

-- =========================================
-- CONSULTA 87
-- Reservas que generaron facturas mayores al promedio.
-- =========================================
SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, f.numero_factura, f.total
FROM reservas AS r
JOIN detalles_venta AS dv ON dv.id_reserva = r.id_reserva AND dv.concepto = 'RESERVA'
JOIN facturas AS f ON f.id_venta = dv.id_venta
WHERE f.estado <> 'ANULADA'
  AND f.total > (SELECT AVG(total) FROM facturas WHERE estado <> 'ANULADA')
ORDER BY f.total DESC;

-- =========================================
-- CONSULTA 88
-- Porcentaje de ocupación global del coworking por mes.
-- Horas ocupadas (CONFIRMADA, FINALIZADA o NO_SHOW) / horas disponibles.
-- Horas disponibles = horas de atención de cada sede (horarios_atencion)
-- x número de espacios de la sede, día por día (calendario con CTE recursivo).
-- =========================================
WITH RECURSIVE dias AS (
    SELECT DATE(MIN(fecha_inicio)) AS dia, DATE(MAX(fecha_inicio)) AS ultimo FROM reservas
    UNION ALL
    SELECT dia + INTERVAL 1 DAY, ultimo FROM dias WHERE dia < ultimo
),
disponible AS (
    SELECT DATE_FORMAT(d.dia, '%Y-%m') AS mes,
           SUM(TIME_TO_SEC(TIMEDIFF(h.hora_fin, h.hora_inicio)) / 3600) AS horas_disponibles
    FROM dias d
    JOIN espacios e
    JOIN horarios_atencion h
      ON h.id_sede_coworking = e.id_sede_coworking
     AND h.dia_semana = ELT(WEEKDAY(d.dia) + 1, 'LUNES','MARTES','MIERCOLES',
                            'JUEVES','VIERNES','SABADO','DOMINGO')
    GROUP BY DATE_FORMAT(d.dia, '%Y-%m')
),
ocupado AS (
    SELECT DATE_FORMAT(fecha_inicio, '%Y-%m') AS mes,
           SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / 60 AS horas_ocupadas
    FROM reservas
    WHERE estado IN ('CONFIRMADA', 'FINALIZADA', 'NO_SHOW')
    GROUP BY DATE_FORMAT(fecha_inicio, '%Y-%m')
)
SELECT d.mes,
       ROUND(COALESCE(o.horas_ocupadas, 0), 1)                             AS horas_ocupadas,
       ROUND(d.horas_disponibles, 1)                                       AS horas_disponibles,
       ROUND(COALESCE(o.horas_ocupadas, 0) * 100 / d.horas_disponibles, 2) AS porcentaje_ocupacion
FROM disponible d
LEFT JOIN ocupado o ON o.mes = d.mes
ORDER BY d.mes;

-- =========================================
-- CONSULTA 89
-- Usuarios con más horas de reserva que el promedio del sistema.
-- =========================================
SELECT u.id_usuario, u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
       ROUND(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 2) AS horas_reservadas
FROM reservas AS r
JOIN usuarios AS u ON u.id_usuario = r.id_usuario
JOIN personas AS p ON p.id_persona = u.id_persona
WHERE r.estado <> 'CANCELADA'
GROUP BY u.id_usuario, u.nombre_usuario, p.primer_nombre, p.primer_apellido
HAVING SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) > (
    SELECT SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / COUNT(DISTINCT id_usuario)
    FROM reservas
    WHERE estado <> 'CANCELADA'
)
ORDER BY horas_reservadas DESC;

-- =========================================
-- CONSULTA 90
-- Top 3 de salas más usadas en el último trimestre (últimos 3 meses)
-- =========================================
SELECT e.id_espacio, e.nombre, e.tipo_espacio,
       COUNT(*) AS reservas
FROM reservas AS r
JOIN espacios AS e ON e.id_espacio = r.id_espacio
WHERE e.tipo_espacio IN ('SALA_REUNIONES', 'SALA_EVENTOS')
  AND r.estado IN ('CONFIRMADA', 'FINALIZADA')
  AND r.fecha_inicio >= CURRENT_DATE() - INTERVAL 3 MONTH
GROUP BY e.id_espacio, e.nombre, e.tipo_espacio
ORDER BY reservas DESC
LIMIT 3;

-- =========================================
-- CONSULTA 91
-- Ingresos promedio por tipo de membresía.
-- =========================================
SELECT m.tipo_membresia,
       COUNT(*) AS membresias_vendidas,
       ROUND(AVG(dv.precio), 2) AS ingreso_promedio,
       SUM(dv.precio) AS ingresos_totales
FROM detalles_venta AS dv
JOIN suscripciones AS s ON s.id_suscripcion = dv.id_suscripcion
JOIN membresias AS m ON m.id_membresia = s.id_membresia
JOIN facturas AS f ON f.id_venta = dv.id_venta AND f.estado <> 'ANULADA'
GROUP BY m.tipo_membresia
ORDER BY ingreso_promedio DESC;

-- =========================================
-- CONSULTA 92
-- Usuarios que pagan solo con un método de pago (subconsulta)
-- =========================================
SELECT DISTINCT u.id_usuario, u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
       mp.nombre AS metodo_pago
FROM usuarios AS u
JOIN personas AS p ON p.id_persona = u.id_persona
JOIN ventas AS v ON v.id_usuario = u.id_usuario
JOIN pagos AS pg ON pg.id_venta = v.id_venta AND pg.estado = 'PAGADO'
JOIN metodos_pago AS mp ON mp.id_metodo_pago = pg.id_metodo_pago
WHERE u.id_usuario IN (
    SELECT v2.id_usuario
    FROM ventas AS v2
    JOIN pagos AS pg2 ON pg2.id_venta = v2.id_venta AND pg2.estado = 'PAGADO'
    WHERE v2.id_usuario IS NOT NULL
    GROUP BY v2.id_usuario
    HAVING COUNT(DISTINCT pg2.id_metodo_pago) = 1
);

-- =========================================
-- CONSULTA 93
-- Reservas canceladas por usuarios que nunca asistieron.
-- =========================================
SELECT r.id_reserva, r.fecha_inicio, u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre
FROM reservas AS r
JOIN usuarios AS u ON u.id_usuario = r.id_usuario
JOIN personas AS p ON p.id_persona = u.id_persona
WHERE r.estado = 'CANCELADA'
AND r.id_usuario NOT IN (SELECT id_usuario FROM registro_asistencias);

-- =========================================
-- CONSULTA 94
-- Facturas con pagos parciales y su saldo pendiente.
-- =========================================
SELECT f.numero_factura, f.total,
       SUM(pg.monto) AS total_pagado,
       f.total - SUM(pg.monto) AS saldo_pendiente
FROM facturas AS f
JOIN pagos AS pg ON pg.id_venta = f.id_venta AND pg.estado = 'PAGADO'
WHERE f.estado <> 'ANULADA'
GROUP BY f.id_factura, f.numero_factura, f.total
HAVING SUM(pg.monto) < f.total;

-- =========================================
-- CONSULTA 95
-- Facturación total de cada empresa, de mayor a menor.
-- =========================================
SELECT e.id_empresa, e.razon_social,
       COALESCE(SUM(f.total), 0) AS facturacion_total
FROM empresas AS e
LEFT JOIN ventas AS v   ON v.id_empresa = e.id_empresa
LEFT JOIN facturas AS f ON f.id_venta = v.id_venta AND f.estado <> 'ANULADA'
GROUP BY e.id_empresa, e.razon_social
ORDER BY facturacion_total DESC;

-- =========================================
-- CONSULTA 96
-- Usuarios que superan en reservas al promedio de su empresa.
-- =========================================
SELECT t.razon_social, t.nombre_usuario, t.nombre, t.reservas,
       ROUND(t.promedio_empresa, 2) AS promedio_empresa
FROM (
    SELECT e.razon_social, u.nombre_usuario,
           CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
           COUNT(r.id_reserva) AS reservas,
           AVG(COUNT(r.id_reserva)) OVER (PARTITION BY e.id_empresa) AS promedio_empresa
    FROM empleados_empresa AS ee
    JOIN empresas AS e ON e.id_empresa = ee.id_empresa
    JOIN usuarios AS u ON u.id_persona = ee.id_persona
    JOIN personas AS p ON p.id_persona = u.id_persona
    LEFT JOIN reservas AS r ON r.id_usuario = u.id_usuario
    GROUP BY e.id_empresa, e.razon_social, u.id_usuario, u.nombre_usuario, p.primer_nombre, p.primer_apellido
    ) AS t
WHERE t.reservas > t.promedio_empresa;

-- =========================================
-- CONSULTA 97
-- Las 3 empresas con más empleados activos en el coworking.
-- =========================================
SELECT e.id_empresa,
       e.razon_social,
       COUNT(DISTINCT u.id_usuario) AS empleados_activos
FROM empresas AS e
JOIN empleados_empresa AS ee ON ee.id_empresa = e.id_empresa
JOIN usuarios AS u ON u.id_persona = ee.id_persona
JOIN suscripciones AS s ON s.id_usuario = u.id_usuario
                       AND s.estado = 'ACTIVA'
                       AND CURDATE() >= s.fecha_inicio AND CURDATE() < s.fecha_fin
GROUP BY e.id_empresa, e.razon_social
ORDER BY empleados_activos DESC
LIMIT 3;

-- =========================================
-- CONSULTA 98
-- Porcentaje de usuarios activos frente al total de registrados.
-- =========================================
SELECT (SELECT COUNT(*) FROM usuarios) AS total_usuarios,
       COUNT(DISTINCT s.id_usuario) AS usuarios_activos,
       ROUND(COUNT(DISTINCT s.id_usuario) * 100 / (SELECT COUNT(*) FROM usuarios), 2) AS porcentaje_activos
FROM suscripciones AS s
WHERE s.estado = 'ACTIVA'
  AND CURDATE() >= s.fecha_inicio AND CURDATE() < s.fecha_fin;

-- =========================================
-- CONSULTA 99
-- Ingresos mensuales acumulados (función de ventana OVER)
-- =========================================
SELECT t.mes, t.ingresos,
       SUM(t.ingresos) OVER (ORDER BY t.mes) AS ingresos_acumulados
FROM (SELECT DATE_FORMAT(f.fecha_emision, '%Y-%m') AS mes,
             SUM(f.subtotal) AS ingresos
        FROM facturas f
       WHERE f.estado <> 'ANULADA'
       GROUP BY DATE_FORMAT(f.fecha_emision, '%Y-%m')
     ) AS t
ORDER BY t.mes;

-- =========================================
-- CONSULTA 100
-- Usuarios con más de 10 reservas, más de $500 en facturación y.
-- membresía activa (múltiples joins y subconsultas correlacionadas)
-- =========================================
SELECT DISTINCT u.id_usuario, u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre
FROM usuarios AS u
JOIN personas AS p ON p.id_persona = u.id_persona
JOIN suscripciones AS s ON s.id_usuario = u.id_usuario
                       AND s.estado = 'ACTIVA'
                       AND CURDATE() >= s.fecha_inicio AND CURDATE() < s.fecha_fin
WHERE (SELECT COUNT(*)
       FROM reservas AS r
       WHERE r.id_usuario = u.id_usuario) > 10
  AND (SELECT SUM(f.total)
       FROM ventas AS v
       JOIN facturas AS f ON f.id_venta = v.id_venta
       WHERE v.id_usuario = u.id_usuario
         AND f.estado <> 'ANULADA') > 500;
