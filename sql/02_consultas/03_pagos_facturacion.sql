/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Pagos y Facturación
Archivo: 03_pagos_facturacion.sql
Descripción:
  Consultas 41 a 60 del módulo.
  Criterios usados:
    * Ingresos = valores SIN IVA (subtotal / precio del detalle) de
                 facturas que no están ANULADAS.
    * Pagado / recaudado = pagos en estado PAGADO (incluyen IVA).
Requisitos:
  Ejecutar previamente DDL, DML y funciones (Q50 y Q51 usan fn_total_pagado).
  Para reproducir los resultados documentados ejecutar antes:
    SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');
*/
USE coworking_grupo5;

-- =========================================
-- CONSULTA 41
-- Listar todos los pagos realizados con método tarjeta.
-- =========================================
SELECT p.id_pago,
       p.fecha_pago,
       p.monto,
       p.estado,
       COALESCE(u.nombre_usuario, em.razon_social) AS pagador,
       f.numero_factura
FROM pagos p
JOIN metodos_pago mp ON mp.id_metodo_pago = p.id_metodo_pago
JOIN ventas v        ON v.id_venta = p.id_venta
LEFT JOIN usuarios u  ON u.id_usuario  = v.id_usuario
LEFT JOIN empresas em ON em.id_empresa = v.id_empresa
LEFT JOIN facturas f  ON f.id_venta    = v.id_venta
WHERE mp.nombre = 'Tarjeta'
  AND p.estado  = 'PAGADO'
ORDER BY p.fecha_pago DESC;

-- =========================================
-- CONSULTA 42
-- Listar pagos pendientes de usuarios (transacción en estado PENDIENTE).
-- =========================================
SELECT p.id_pago,
       u.id_usuario,
       u.nombre_usuario,
       mp.nombre       AS metodo,
       p.monto,
       p.fecha_pago,
       f.numero_factura,
       f.saldo_pendiente
FROM pagos p
JOIN ventas v         ON v.id_venta = p.id_venta
JOIN usuarios u       ON u.id_usuario = v.id_usuario
JOIN metodos_pago mp  ON mp.id_metodo_pago = p.id_metodo_pago
LEFT JOIN facturas f  ON f.id_venta = v.id_venta
WHERE p.estado = 'PENDIENTE'
ORDER BY p.fecha_pago;

-- =========================================
-- CONSULTA 43
-- Mostrar pagos cancelados en los últimos 3 meses.
-- =========================================
SELECT p.id_pago,
       p.fecha_pago,
       p.monto,
       mp.nombre                                   AS metodo,
       COALESCE(u.nombre_usuario, em.razon_social) AS pagador
FROM pagos p
JOIN metodos_pago mp  ON mp.id_metodo_pago = p.id_metodo_pago
JOIN ventas v         ON v.id_venta = p.id_venta
LEFT JOIN usuarios u  ON u.id_usuario  = v.id_usuario
LEFT JOIN empresas em ON em.id_empresa = v.id_empresa
WHERE p.estado = 'CANCELADO'
  AND p.fecha_pago >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
ORDER BY p.fecha_pago DESC;

-- =========================================
-- CONSULTA 44
-- Listar facturas generadas por membresías.
-- =========================================
SELECT f.numero_factura,
       f.fecha_emision,
       COALESCE(u.nombre_usuario, em.razon_social)   AS cliente,
       COUNT(d.id_detalle)                            AS membresias,
       f.total,
       f.estado
FROM facturas f
JOIN ventas v         ON v.id_venta = f.id_venta
JOIN detalles_venta d ON d.id_venta = v.id_venta AND d.concepto = 'MEMBRESIA'
LEFT JOIN usuarios u  ON u.id_usuario  = v.id_usuario
LEFT JOIN empresas em ON em.id_empresa = v.id_empresa
GROUP BY f.id_factura, f.numero_factura, f.fecha_emision, cliente, f.total, f.estado
ORDER BY f.fecha_emision DESC;

-- =========================================
-- CONSULTA 45
-- Listar facturas generadas por reservas.
-- =========================================
SELECT f.numero_factura,
       f.fecha_emision,
       COALESCE(u.nombre_usuario, em.razon_social)   AS cliente,
       COUNT(d.id_detalle)                            AS reservas,
       f.total,
       f.estado
FROM facturas f
JOIN ventas v         ON v.id_venta = f.id_venta
JOIN detalles_venta d ON d.id_venta = v.id_venta AND d.concepto = 'RESERVA'
LEFT JOIN usuarios u  ON u.id_usuario  = v.id_usuario
LEFT JOIN empresas em ON em.id_empresa = v.id_empresa
GROUP BY f.id_factura, f.numero_factura, f.fecha_emision, cliente, f.total, f.estado
ORDER BY f.fecha_emision DESC;

-- =========================================
-- CONSULTA 46
-- Mostrar el total de ingresos por membresías en el último mes (sin IVA).
-- =========================================
SELECT COUNT(*)                   AS membresias_vendidas,
       COALESCE(SUM(d.precio), 0) AS ingresos_membresias
FROM detalles_venta d
JOIN facturas f ON f.id_venta = d.id_venta
WHERE d.concepto = 'MEMBRESIA'
  AND f.estado  <> 'ANULADA'
  AND f.fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH);

-- =========================================
-- CONSULTA 47
-- Mostrar el total de ingresos por reservas en el último mes (sin IVA).
-- =========================================
SELECT COUNT(*)                   AS reservas_facturadas,
       COALESCE(SUM(d.precio), 0) AS ingresos_reservas
FROM detalles_venta d
JOIN facturas f ON f.id_venta = d.id_venta
WHERE d.concepto = 'RESERVA'
  AND f.estado  <> 'ANULADA'
  AND f.fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH);

-- =========================================
-- CONSULTA 48
-- Mostrar el total de ingresos por servicios adicionales (sin IVA),
-- por servicio y con el total general (WITH ROLLUP).
-- =========================================
SELECT COALESCE(sv.nombre, 'TOTAL')  AS servicio,
       SUM(su.cantidad)              AS unidades,
       SUM(d.precio)                 AS ingresos
FROM detalles_venta d
JOIN facturas f          ON f.id_venta = d.id_venta AND f.estado <> 'ANULADA'
JOIN servicio_usuario su ON su.id_servicio_usuario = d.id_servicio_usuario
JOIN servicios sv        ON sv.id_servicio = su.id_servicio
WHERE d.concepto = 'SERVICIO'
GROUP BY sv.nombre WITH ROLLUP;

-- =========================================
-- CONSULTA 49
-- Identificar usuarios que nunca han pagado con PayPal
-- (entre los que sí han realizado pagos).
-- =========================================
SELECT u.id_usuario, u.nombre_usuario
FROM usuarios u
WHERE EXISTS (SELECT 1 FROM ventas v JOIN pagos p ON p.id_venta = v.id_venta
               WHERE v.id_usuario = u.id_usuario AND p.estado = 'PAGADO')
  AND NOT EXISTS (SELECT 1
                    FROM ventas v
                    JOIN pagos p         ON p.id_venta = v.id_venta
                    JOIN metodos_pago mp ON mp.id_metodo_pago = p.id_metodo_pago
                   WHERE v.id_usuario = u.id_usuario
                     AND mp.nombre = 'PayPal')
ORDER BY u.id_usuario;

-- =========================================
-- CONSULTA 50
-- Calcular el promedio de gasto por usuario (usuarios que han pagado algo).
-- =========================================
SELECT COUNT(*)                     AS usuarios_con_pagos,
       ROUND(AVG(total_pagado), 2)  AS promedio_gasto_por_usuario,
       MAX(total_pagado)            AS gasto_maximo,
       MIN(total_pagado)            AS gasto_minimo
FROM (SELECT u.id_usuario, fn_total_pagado(u.id_usuario) AS total_pagado
        FROM usuarios u) t
WHERE total_pagado > 0;

-- =========================================
-- CONSULTA 51
-- Mostrar el top 5 de usuarios que más han pagado en total.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       fn_total_pagado(u.id_usuario) AS total_pagado
FROM usuarios u
ORDER BY total_pagado DESC
LIMIT 5;

-- =========================================
-- CONSULTA 52
-- Mostrar facturas con monto mayor a $1000.
-- =========================================
SELECT f.numero_factura,
       f.fecha_emision,
       COALESCE(u.nombre_usuario, em.razon_social) AS cliente,
       f.total,
       f.estado
FROM facturas f
JOIN ventas v         ON v.id_venta = f.id_venta
LEFT JOIN usuarios u  ON u.id_usuario  = v.id_usuario
LEFT JOIN empresas em ON em.id_empresa = v.id_empresa
WHERE f.total > 1000
ORDER BY f.total DESC;

-- =========================================
-- CONSULTA 53
-- Listar pagos realizados después de la fecha de vencimiento de su factura.
-- =========================================
SELECT p.id_pago,
       f.numero_factura,
       f.fecha_vencimiento,
       DATE(p.fecha_pago)                               AS fecha_pago,
       DATEDIFF(DATE(p.fecha_pago), f.fecha_vencimiento) AS dias_de_atraso,
       p.monto,
       COALESCE(u.nombre_usuario, em.razon_social)      AS pagador
FROM pagos p
JOIN facturas f       ON f.id_venta = p.id_venta
JOIN ventas v         ON v.id_venta = p.id_venta
LEFT JOIN usuarios u  ON u.id_usuario  = v.id_usuario
LEFT JOIN empresas em ON em.id_empresa = v.id_empresa
WHERE p.estado = 'PAGADO'
  AND DATE(p.fecha_pago) > f.fecha_vencimiento
ORDER BY dias_de_atraso DESC;

-- =========================================
-- CONSULTA 54
-- Calcular el total recaudado en el año actual (pagos recibidos, con IVA).
-- =========================================
SELECT YEAR(CURDATE())          AS anio,
       COUNT(*)                 AS pagos,
       COALESCE(SUM(monto), 0)  AS total_recaudado
FROM pagos
WHERE estado = 'PAGADO'
  AND YEAR(fecha_pago) = YEAR(CURDATE());

-- =========================================
-- CONSULTA 55
-- Mostrar facturas anuladas y su motivo.
-- =========================================
SELECT f.numero_factura,
       f.fecha_emision,
       COALESCE(u.nombre_usuario, em.razon_social) AS cliente,
       f.total,
       f.motivo_anulacion
FROM facturas f
JOIN ventas v         ON v.id_venta = f.id_venta
LEFT JOIN usuarios u  ON u.id_usuario  = v.id_usuario
LEFT JOIN empresas em ON em.id_empresa = v.id_empresa
WHERE f.estado = 'ANULADA'
ORDER BY f.fecha_emision DESC;

-- =========================================
-- CONSULTA 56
-- Mostrar usuarios con facturas pendientes mayores a $200 (saldo pendiente).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*)                AS facturas_pendientes,
       SUM(f.saldo_pendiente)  AS saldo_total,
       MAX(f.saldo_pendiente)  AS mayor_saldo
FROM facturas f
JOIN ventas v   ON v.id_venta = f.id_venta
JOIN usuarios u ON u.id_usuario = v.id_usuario
WHERE f.estado = 'PENDIENTE'
  AND f.saldo_pendiente > 200
GROUP BY u.id_usuario, u.nombre_usuario
ORDER BY saldo_total DESC;

-- =========================================
-- CONSULTA 57
-- Mostrar usuarios que han pagado más de una vez el mismo servicio.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       sv.nombre         AS servicio,
       COUNT(*)          AS veces_pagado,
       SUM(d.precio)     AS total
FROM detalles_venta d
JOIN ventas v            ON v.id_venta = d.id_venta
JOIN facturas f          ON f.id_venta = v.id_venta AND f.estado = 'PAGADA'
JOIN servicio_usuario su ON su.id_servicio_usuario = d.id_servicio_usuario
JOIN servicios sv        ON sv.id_servicio = su.id_servicio
JOIN usuarios u          ON u.id_usuario = v.id_usuario
WHERE d.concepto = 'SERVICIO'
GROUP BY u.id_usuario, u.nombre_usuario, sv.nombre
HAVING COUNT(*) > 1
ORDER BY veces_pagado DESC, u.id_usuario;

-- =========================================
-- CONSULTA 58
-- Listar ingresos por cada método de pago (pagos PAGADO).
-- =========================================
SELECT mp.nombre                  AS metodo_pago,
       COUNT(p.id_pago)           AS pagos,
       COALESCE(SUM(p.monto), 0)  AS total_recaudado,
       ROUND(COALESCE(SUM(p.monto), 0) * 100
             / (SELECT SUM(monto) FROM pagos WHERE estado = 'PAGADO'), 2) AS porcentaje
FROM metodos_pago mp
LEFT JOIN pagos p ON p.id_metodo_pago = mp.id_metodo_pago AND p.estado = 'PAGADO'
GROUP BY mp.id_metodo_pago, mp.nombre
ORDER BY total_recaudado DESC;

-- =========================================
-- CONSULTA 59
-- Mostrar facturación acumulada por empresa: total facturado cada mes
-- y acumulado en el tiempo (función de ventana).
-- =========================================
SELECT em.razon_social,
       DATE_FORMAT(f.fecha_emision, '%Y-%m')  AS mes,
       SUM(f.total)                           AS facturado_mes,
       SUM(SUM(f.total)) OVER (PARTITION BY em.id_empresa
                               ORDER BY DATE_FORMAT(f.fecha_emision, '%Y-%m')) AS facturado_acumulado
FROM facturas f
JOIN ventas v    ON v.id_venta = f.id_venta
JOIN empresas em ON em.id_empresa = v.id_empresa
WHERE f.estado <> 'ANULADA'
GROUP BY em.id_empresa, em.razon_social, DATE_FORMAT(f.fecha_emision, '%Y-%m')
ORDER BY em.razon_social, mes;

-- =========================================
-- CONSULTA 60
-- Mostrar ingresos netos por mes del último año.
-- Ingreso neto = subtotal sin IVA de facturas no anuladas menos los
-- reembolsos del mes (convertidos a valor sin IVA).
-- =========================================
WITH facturado AS (
    SELECT DATE_FORMAT(fecha_emision, '%Y-%m') AS mes,
           SUM(subtotal) AS ingresos_sin_iva,
           SUM(iva)      AS iva
    FROM facturas
    WHERE estado <> 'ANULADA'
      AND fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY DATE_FORMAT(fecha_emision, '%Y-%m')
),
reembolsado AS (
    SELECT DATE_FORMAT(fecha, '%Y-%m') AS mes,
           ROUND(SUM(monto) / 1.19, 2) AS reembolsos_sin_iva
    FROM reembolsos
    WHERE fecha >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY DATE_FORMAT(fecha, '%Y-%m')
)
SELECT f.mes,
       f.ingresos_sin_iva,
       f.iva,
       COALESCE(r.reembolsos_sin_iva, 0)                       AS reembolsos_sin_iva,
       f.ingresos_sin_iva - COALESCE(r.reembolsos_sin_iva, 0)  AS ingresos_netos
FROM facturado f
LEFT JOIN reembolsado r ON r.mes = f.mes
ORDER BY f.mes;
