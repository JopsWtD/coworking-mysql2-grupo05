/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Usuarios y Membresías
Archivo: 01_usuarios_membresias.sql
Descripción:
  Consultas 01 a 20 del módulo.
  Las consultas Q02, Q03, Q04, Q09, Q14, Q15 y Q18 usan las funciones de
  03_funciones/01_funciones.sql. Las comparaciones con el texto que
  devuelven las funciones usan _utf8mb4'...' COLLATE utf8mb4_unicode_ci
  para que funcionen con cualquier juego de caracteres de la conexión.
Requisitos:
  Ejecutar previamente DDL, DML y funciones.
  Para reproducir los resultados documentados ejecutar antes:
    SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');
*/
USE coworking_grupo5;
-- =========================================
-- CONSULTA 01
-- Listar todos los usuarios con su información básica.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.segundo_nombre,
                      p.primer_apellido, p.segundo_apellido) AS nombre_completo,
       p.tipo_documento,
       p.numero_documento,
       TIMESTAMPDIFF(YEAR, p.fecha_nacimiento, CURDATE())    AS edad,
       p.email,
       p.telefono,
       u.fecha_registro
FROM usuarios u
JOIN personas p ON p.id_persona = u.id_persona
ORDER BY u.id_usuario;

-- =========================================
-- CONSULTA 02
-- Listar los usuarios con membresía activa.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       fn_tipo_membresia(u.id_usuario)             AS tipo_membresia,
       fn_dias_restantes_membresia(u.id_usuario)   AS dias_restantes
FROM usuarios u
WHERE fn_membresia_activa(u.id_usuario) = TRUE
ORDER BY u.id_usuario;

-- =========================================
-- CONSULTA 03
-- Listar los usuarios cuya membresía está vencida.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       fn_estado_membresia(u.id_usuario) AS estado
FROM usuarios u
WHERE fn_estado_membresia(u.id_usuario) = _utf8mb4'VENCIDA' COLLATE utf8mb4_unicode_ci;

-- =========================================
-- CONSULTA 04
-- Listar los usuarios con membresía suspendida.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       fn_estado_membresia(u.id_usuario) AS estado
FROM usuarios u
WHERE fn_estado_membresia(u.id_usuario) = _utf8mb4'SUSPENDIDA' COLLATE utf8mb4_unicode_ci;

-- =========================================
-- CONSULTA 05
-- Contar cuántos usuarios tienen cada tipo de membresía (activas).
-- LEFT JOIN para que aparezcan también los tipos con 0 usuarios
-- =========================================
SELECT m.tipo_membresia,
       COUNT(DISTINCT s.id_usuario) AS usuarios
FROM membresias m
LEFT JOIN suscripciones s
       ON s.id_membresia = m.id_membresia
      AND s.estado = 'ACTIVA'
GROUP BY m.tipo_membresia
ORDER BY usuarios DESC;

-- =========================================
-- CONSULTA 06
-- Top 10 de usuarios con más antigüedad en el coworking.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       u.fecha_registro,
       TIMESTAMPDIFF(MONTH, u.fecha_registro, CURDATE()) AS antiguedad_meses
FROM usuarios u
ORDER BY u.fecha_registro ASC
LIMIT 10;

-- =========================================
-- CONSULTA 07
-- Listar usuarios que pertenecen a una empresa específica.
-- Cambiar el NIT por el de la empresa a consultar (901234567-1 = Innovatek).
-- =========================================
SELECT e.razon_social,
       u.id_usuario,
       u.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
       IF(ee.es_gerente, 'GERENTE', 'EMPLEADO')           AS rol
FROM empresas e
JOIN empleados_empresa ee ON ee.id_empresa = e.id_empresa
JOIN personas p           ON p.id_persona  = ee.id_persona
JOIN usuarios u           ON u.id_persona  = p.id_persona
WHERE e.nit_empresa = '901234567-1';

-- =========================================
-- CONSULTA 08
-- Contar cuántos usuarios están asociados a cada empresa.
-- =========================================
SELECT e.id_empresa,
       e.razon_social,
       COUNT(u.id_usuario) AS usuarios
FROM empresas e
LEFT JOIN empleados_empresa ee ON ee.id_empresa = e.id_empresa
LEFT JOIN usuarios u           ON u.id_persona  = ee.id_persona
GROUP BY e.id_empresa, e.razon_social
ORDER BY usuarios DESC;

-- =========================================
-- CONSULTA 09
-- Mostrar usuarios que nunca han hecho una reserva.
-- =========================================
SELECT u.id_usuario, u.nombre_usuario
FROM usuarios u
WHERE fn_total_reservas(u.id_usuario) = 0;

-- =========================================
-- CONSULTA 10
-- Mostrar usuarios con más de 5 reservas activas en el mes actual.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*) AS reservas_activas_mes
FROM reservas r
JOIN usuarios u ON u.id_usuario = r.id_usuario
WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA')
  AND r.fecha_inicio >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
  AND r.fecha_inicio <  DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
GROUP BY u.id_usuario, u.nombre_usuario
HAVING COUNT(*) > 5;

-- =========================================
-- CONSULTA 11
-- Calcular el promedio de edad de los usuarios.
-- =========================================
SELECT ROUND(AVG(TIMESTAMPDIFF(YEAR, p.fecha_nacimiento, CURDATE())), 1) AS promedio_edad
FROM usuarios u
JOIN personas p ON p.id_persona = u.id_persona;

-- =========================================
-- CONSULTA 12
-- Listar usuarios que han cambiado de membresía más de 2 veces.
-- Un cambio = una suscripción con tipo distinto al de la anterior del mismo usuario
-- =========================================
WITH historial AS (
  SELECT id_usuario,
         id_membresia,
         LAG(id_membresia) OVER (PARTITION BY id_usuario
                                 ORDER BY fecha_inicio, id_suscripcion) AS membresia_anterior
  FROM suscripciones
)
SELECT u.id_usuario,
       u.nombre_usuario,
       SUM(h.membresia_anterior IS NOT NULL
           AND h.membresia_anterior <> h.id_membresia) AS cambios
FROM historial h
JOIN usuarios u ON u.id_usuario = h.id_usuario
GROUP BY u.id_usuario, u.nombre_usuario
HAVING cambios > 2;

-- =========================================
-- CONSULTA 13
-- Listar usuarios que han gastado más de $500 en reservas.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       SUM(dv.precio) AS total_en_reservas
FROM detalles_venta dv
JOIN facturas f ON f.id_venta   = dv.id_venta
               AND f.estado    <> 'ANULADA'      -- no cuenta reservas anuladas
JOIN reservas r ON r.id_reserva = dv.id_reserva
JOIN usuarios u ON u.id_usuario = r.id_usuario
WHERE dv.concepto = 'RESERVA'
GROUP BY u.id_usuario, u.nombre_usuario
HAVING SUM(dv.precio) > 500
ORDER BY total_en_reservas DESC;

-- =========================================
-- CONSULTA 14
-- Mostrar usuarios que tienen tanto membresía (activa) como servicios adicionales.
-- =========================================
SELECT u.id_usuario, u.nombre_usuario
FROM usuarios u
WHERE fn_membresia_activa(u.id_usuario) = TRUE
  AND EXISTS (SELECT 1
                FROM servicio_usuario su
               WHERE su.id_usuario = u.id_usuario);

-- =========================================
-- CONSULTA 15
-- Listar usuarios con membresía Premium y reservas activas.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       fn_reservas_activas(u.id_usuario) AS reservas_activas
FROM usuarios u
WHERE fn_tipo_membresia(u.id_usuario) = _utf8mb4'PREMIUM' COLLATE utf8mb4_unicode_ci
  AND fn_reservas_activas(u.id_usuario) > 0;

-- =========================================
-- CONSULTA 16
-- Mostrar usuarios con membresía Corporativa y su empresa.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       e.razon_social AS empresa,
       s.fecha_fin
FROM suscripciones s
JOIN membresias m         ON m.id_membresia = s.id_membresia
JOIN usuarios u           ON u.id_usuario   = s.id_usuario
JOIN empleados_empresa ee ON ee.id_persona  = u.id_persona
JOIN empresas e           ON e.id_empresa   = ee.id_empresa
WHERE m.tipo_membresia = 'CORPORATIVA'
  AND s.estado = 'ACTIVA'
ORDER BY e.razon_social, u.nombre_usuario;

-- =========================================
-- CONSULTA 17
-- Identificar usuarios con membresía diaria que la han renovado más de 10 veces.
-- Renovaciones = cantidad de suscripciones DIARIA menos la primera
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*) - 1 AS renovaciones
FROM suscripciones s
JOIN membresias m ON m.id_membresia = s.id_membresia
JOIN usuarios u   ON u.id_usuario   = s.id_usuario
WHERE m.tipo_membresia = 'DIARIA'
GROUP BY u.id_usuario, u.nombre_usuario
HAVING COUNT(*) - 1 > 10;

-- =========================================
-- CONSULTA 18
-- Mostrar usuarios cuya membresía vence en los próximos 7 días.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       p.email,
       fn_tipo_membresia(u.id_usuario)           AS tipo_membresia,
       fn_dias_restantes_membresia(u.id_usuario) AS dias_restantes
FROM usuarios u
JOIN personas p ON p.id_persona = u.id_persona
WHERE fn_membresia_activa(u.id_usuario) = TRUE
  AND fn_dias_restantes_membresia(u.id_usuario) BETWEEN 0 AND 7
ORDER BY dias_restantes;

-- =========================================
-- CONSULTA 19
-- Listar usuarios que se registraron en el último mes.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       u.fecha_registro
FROM usuarios u
WHERE u.fecha_registro >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
ORDER BY u.fecha_registro DESC;

-- =========================================
-- CONSULTA 20
-- Mostrar usuarios que nunca han asistido al coworking (0 accesos permitidos).
-- =========================================
SELECT u.id_usuario, u.nombre_usuario
FROM usuarios u
WHERE NOT EXISTS (SELECT 1
                    FROM control_acceso ca
                   WHERE ca.id_usuario = u.id_usuario
                     AND ca.resultado  = 'PERMITIDO');
