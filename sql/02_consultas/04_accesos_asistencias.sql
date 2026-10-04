/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Accesos y Asistencias
Archivo: 04_accesos_asistencias.sql
Descripción:
  Consultas 61 a 80 del módulo.
  Criterios usados:
    * Acceso     = cualquier intento en control_acceso (permitido o no).
    * Asistencia = acceso PERMITIDO (tabla registro_asistencias).
    * Mañana: entrada antes de las 12:00. Noche: entrada desde las 17:00.
Requisitos:
  Ejecutar previamente DDL, DML y funciones (Q63 usa fn_ultima_asistencia).
  Para reproducir los resultados documentados ejecutar antes:
    SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');
*/
USE coworking_grupo5;

-- =========================================
-- CONSULTA 61
-- Listar todos los accesos registrados hoy.
-- =========================================
SELECT c.id_control,
       COALESCE(u.nombre_usuario, '(codigo invalido)') AS usuario,
       s.nombre_sede,
       c.hora_entrada,
       c.hora_salida,
       c.metodo,
       c.resultado,
       c.motivo_rechazo
FROM control_acceso c
JOIN sedes_coworking s ON s.id_sede_coworking = c.id_sede_coworking
LEFT JOIN usuarios u   ON u.id_usuario = c.id_usuario
WHERE c.fecha = CURDATE()
ORDER BY c.hora_entrada;

-- =========================================
-- CONSULTA 62
-- Mostrar usuarios con más de 20 asistencias en el mes (últimos 30 días).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*) AS asistencias_mes
FROM registro_asistencias a
JOIN usuarios u ON u.id_usuario = a.id_usuario
WHERE a.fecha_hora >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND a.fecha_hora <  CURDATE() + INTERVAL 1 DAY
GROUP BY u.id_usuario, u.nombre_usuario
HAVING COUNT(*) > 20
ORDER BY asistencias_mes DESC;

-- =========================================
-- CONSULTA 63
-- Mostrar usuarios que no asistieron en la última semana
-- (usuarios con membresía activa, para detectar inactividad).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       fn_tipo_membresia(u.id_usuario)    AS membresia,
       fn_ultima_asistencia(u.id_usuario) AS ultima_asistencia
FROM usuarios u
WHERE fn_membresia_activa(u.id_usuario)
  AND NOT EXISTS (SELECT 1
                    FROM registro_asistencias a
                   WHERE a.id_usuario = u.id_usuario
                     AND a.fecha_hora >= DATE_SUB(CURDATE(), INTERVAL 7 DAY))
ORDER BY ultima_asistencia;

-- =========================================
-- CONSULTA 64
-- Calcular la asistencia promedio por día de la semana.
-- =========================================
SELECT ELT(t.n_dia + 1, 'LUNES','MARTES','MIERCOLES','JUEVES',
           'VIERNES','SABADO','DOMINGO')  AS dia_semana,
       COUNT(*)                            AS dias_con_asistencia,
       ROUND(AVG(t.asistencias), 1)        AS promedio_asistencias
FROM (SELECT DATE(fecha_hora) AS dia, WEEKDAY(fecha_hora) AS n_dia, COUNT(*) AS asistencias
        FROM registro_asistencias
       GROUP BY DATE(fecha_hora), WEEKDAY(fecha_hora)) t
GROUP BY t.n_dia
ORDER BY t.n_dia;

-- =========================================
-- CONSULTA 65
-- Mostrar los 10 usuarios más constantes (más días distintos asistidos).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(DISTINCT DATE(a.fecha_hora)) AS dias_asistidos,
       COUNT(*)                           AS asistencias
FROM registro_asistencias a
JOIN usuarios u ON u.id_usuario = a.id_usuario
GROUP BY u.id_usuario, u.nombre_usuario
ORDER BY dias_asistidos DESC, asistencias DESC
LIMIT 10;

-- =========================================
-- CONSULTA 66
-- Mostrar accesos fuera del horario permitido: intentos rechazados por
-- FUERA_DE_HORARIO o cualquier acceso cuya hora no está dentro del
-- horario de atención de la sede ese día (o la sede no abre ese día).
-- =========================================
SELECT c.id_control,
       c.fecha,
       ELT(WEEKDAY(c.fecha) + 1, 'LUNES','MARTES','MIERCOLES','JUEVES',
           'VIERNES','SABADO','DOMINGO')   AS dia,
       s.nombre_sede,
       c.hora_entrada,
       h.hora_inicio                       AS abre,
       h.hora_fin                          AS cierra,
       COALESCE(u.nombre_usuario, '(codigo invalido)') AS usuario,
       c.resultado
FROM control_acceso c
JOIN sedes_coworking s ON s.id_sede_coworking = c.id_sede_coworking
LEFT JOIN usuarios u   ON u.id_usuario = c.id_usuario
LEFT JOIN horarios_atencion h
       ON h.id_sede_coworking = c.id_sede_coworking
      AND h.dia_semana = ELT(WEEKDAY(c.fecha) + 1, 'LUNES','MARTES','MIERCOLES',
                             'JUEVES','VIERNES','SABADO','DOMINGO')
WHERE c.motivo_rechazo = 'FUERA_DE_HORARIO'
   OR h.id_horario IS NULL
   OR c.hora_entrada < h.hora_inicio
   OR c.hora_entrada >= h.hora_fin
ORDER BY c.fecha DESC, c.hora_entrada;

-- =========================================
-- CONSULTA 67
-- Mostrar usuarios que accedieron sin membresía activa (rechazados).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*)        AS intentos_rechazados,
       MAX(c.fecha)    AS ultimo_intento
FROM control_acceso c
JOIN usuarios u ON u.id_usuario = c.id_usuario
WHERE c.resultado = 'DENEGADO'
  AND c.motivo_rechazo IN ('MEMBRESIA_INACTIVA', 'SIN_RESERVA')
GROUP BY u.id_usuario, u.nombre_usuario
ORDER BY intentos_rechazados DESC;

-- =========================================
-- CONSULTA 68
-- Listar usuarios que solo acceden los fines de semana.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*) AS asistencias
FROM registro_asistencias a
JOIN usuarios u ON u.id_usuario = a.id_usuario
GROUP BY u.id_usuario, u.nombre_usuario
HAVING SUM(DAYOFWEEK(a.fecha_hora) BETWEEN 2 AND 6) = 0;

-- =========================================
-- CONSULTA 69
-- Mostrar usuarios que accedieron más de 2 veces en el mismo día.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       c.fecha,
       COUNT(*) AS accesos
FROM control_acceso c
JOIN usuarios u ON u.id_usuario = c.id_usuario
WHERE c.resultado = 'PERMITIDO'
GROUP BY u.id_usuario, u.nombre_usuario, c.fecha
HAVING COUNT(*) > 2
ORDER BY c.fecha DESC;

-- =========================================
-- CONSULTA 70
-- Mostrar el total de accesos diarios en el último mes.
-- =========================================
SELECT c.fecha,
       COUNT(*)                        AS accesos,
       SUM(c.resultado = 'PERMITIDO')  AS permitidos,
       SUM(c.resultado = 'DENEGADO')   AS denegados
FROM control_acceso c
WHERE c.fecha >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
  AND c.fecha <= CURDATE()
GROUP BY c.fecha
ORDER BY c.fecha;

-- =========================================
-- CONSULTA 71
-- Mostrar usuarios que han accedido pero no tienen reservas.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*) AS asistencias
FROM registro_asistencias a
JOIN usuarios u ON u.id_usuario = a.id_usuario
WHERE NOT EXISTS (SELECT 1 FROM reservas r WHERE r.id_usuario = u.id_usuario)
GROUP BY u.id_usuario, u.nombre_usuario
ORDER BY asistencias DESC;

-- =========================================
-- CONSULTA 72
-- Mostrar los días con más concurrencia en el coworking (top 10).
-- =========================================
SELECT DATE(a.fecha_hora)            AS dia,
       ELT(WEEKDAY(a.fecha_hora) + 1, 'LUNES','MARTES','MIERCOLES','JUEVES',
           'VIERNES','SABADO','DOMINGO') AS dia_semana,
       COUNT(*)                      AS asistencias,
       COUNT(DISTINCT a.id_usuario)  AS usuarios_distintos
FROM registro_asistencias a
GROUP BY DATE(a.fecha_hora), dia_semana
ORDER BY asistencias DESC, dia DESC
LIMIT 10;

-- =========================================
-- CONSULTA 73
-- Mostrar usuarios que entraron pero no registraron salida.
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*)           AS entradas_sin_salida,
       MAX(c.fecha)       AS ultima_vez
FROM control_acceso c
JOIN usuarios u ON u.id_usuario = c.id_usuario
WHERE c.resultado   = 'PERMITIDO'
  AND c.hora_salida IS NULL
GROUP BY u.id_usuario, u.nombre_usuario
ORDER BY entradas_sin_salida DESC, ultima_vez DESC;

-- =========================================
-- CONSULTA 74
-- Mostrar accesos de usuarios con membresía vencida: intentos hechos
-- cuando su última membresía ya había vencido y no tenían otra vigente.
-- =========================================
SELECT c.id_control,
       c.fecha,
       c.hora_entrada,
       u.nombre_usuario,
       (SELECT MAX(s.fecha_fin) FROM suscripciones s
         WHERE s.id_usuario = c.id_usuario AND s.fecha_fin <= c.fecha) AS membresia_vencio_el,
       c.resultado,
       c.motivo_rechazo
FROM control_acceso c
JOIN usuarios u ON u.id_usuario = c.id_usuario
WHERE EXISTS (SELECT 1 FROM suscripciones s
               WHERE s.id_usuario = c.id_usuario
                 AND s.estado     = 'VENCIDA'
                 AND s.fecha_fin <= c.fecha)
  AND NOT EXISTS (SELECT 1 FROM suscripciones s
                   WHERE s.id_usuario = c.id_usuario
                     AND s.estado IN ('ACTIVA', 'VENCIDA')
                     AND c.fecha >= s.fecha_inicio
                     AND c.fecha <  s.fecha_fin)
ORDER BY c.fecha DESC, c.hora_entrada;

-- =========================================
-- CONSULTA 75
-- Mostrar accesos de usuarios corporativos por empresa.
-- =========================================
SELECT em.razon_social,
       COUNT(c.id_control)               AS accesos,
       SUM(c.resultado = 'PERMITIDO')    AS permitidos,
       SUM(c.resultado = 'DENEGADO')     AS denegados,
       COUNT(DISTINCT c.id_usuario)      AS empleados_que_accedieron
FROM empresas em
JOIN empleados_empresa ee ON ee.id_empresa = em.id_empresa
JOIN usuarios u           ON u.id_persona  = ee.id_persona
LEFT JOIN control_acceso c ON c.id_usuario = u.id_usuario
GROUP BY em.id_empresa, em.razon_social
ORDER BY accesos DESC;

-- =========================================
-- CONSULTA 76
-- Mostrar clientes que nunca han usado el coworking a pesar de pagar
-- membresía (tienen membresías pagadas y ninguna asistencia).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(s.id_suscripcion)    AS membresias_pagadas,
       fn_total_pagado(u.id_usuario) AS total_pagado
FROM usuarios u
JOIN suscripciones s ON s.id_usuario = u.id_usuario
                    AND s.estado IN ('ACTIVA', 'VENCIDA')
WHERE NOT EXISTS (SELECT 1 FROM registro_asistencias a WHERE a.id_usuario = u.id_usuario)
GROUP BY u.id_usuario, u.nombre_usuario;

-- =========================================
-- CONSULTA 77
-- Mostrar accesos rechazados por intentos con QR inválido.
-- =========================================
SELECT c.id_control,
       c.fecha,
       c.hora_entrada,
       s.nombre_sede
FROM control_acceso c
JOIN sedes_coworking s ON s.id_sede_coworking = c.id_sede_coworking
WHERE c.resultado      = 'DENEGADO'
  AND c.motivo_rechazo = 'CODIGO_INVALIDO'
  AND c.metodo         = 'QR'
ORDER BY c.fecha DESC, c.hora_entrada;

-- =========================================
-- CONSULTA 78
-- Mostrar accesos promedio por usuario.
-- =========================================
SELECT (SELECT COUNT(*) FROM usuarios)                               AS usuarios_registrados,
       COUNT(DISTINCT c.id_usuario)                                  AS usuarios_con_accesos,
       COUNT(*)                                                      AS accesos_totales,
       ROUND(COUNT(*) / COUNT(DISTINCT c.id_usuario), 2)             AS promedio_por_usuario_activo,
       ROUND(COUNT(*) / (SELECT COUNT(*) FROM usuarios), 2)          AS promedio_por_usuario_registrado,
       fn_promedio_asistencias()                                     AS promedio_asistencias
FROM control_acceso c
WHERE c.id_usuario IS NOT NULL;

-- =========================================
-- CONSULTA 79
-- Identificar usuarios que asisten más en la mañana (antes de las 12:00).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*)                                        AS asistencias,
       SUM(HOUR(a.fecha_hora) < 12)                    AS en_la_manana,
       ROUND(SUM(HOUR(a.fecha_hora) < 12) * 100 / COUNT(*), 1) AS pct_manana
FROM registro_asistencias a
JOIN usuarios u ON u.id_usuario = a.id_usuario
GROUP BY u.id_usuario, u.nombre_usuario
HAVING SUM(HOUR(a.fecha_hora) < 12) > COUNT(*) / 2
ORDER BY pct_manana DESC, asistencias DESC;

-- =========================================
-- CONSULTA 80
-- Identificar usuarios que asisten más en la noche (desde las 17:00).
-- =========================================
SELECT u.id_usuario,
       u.nombre_usuario,
       COUNT(*)                                         AS asistencias,
       SUM(HOUR(a.fecha_hora) >= 17)                    AS en_la_noche,
       ROUND(SUM(HOUR(a.fecha_hora) >= 17) * 100 / COUNT(*), 1) AS pct_noche
FROM registro_asistencias a
JOIN usuarios u ON u.id_usuario = a.id_usuario
GROUP BY u.id_usuario, u.nombre_usuario
HAVING SUM(HOUR(a.fecha_hora) >= 17) > COUNT(*) / 2
ORDER BY pct_noche DESC, asistencias DESC;
