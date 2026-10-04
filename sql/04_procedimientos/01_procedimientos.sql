/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Procedimientos almacenados
Archivo: 01_procedimientos.sql
Descripción:
  20 procedimientos almacenados, organizados por módulo:
    Membresías (4), Reservas y Espacios (5), Pagos y Facturación (4),
    Accesos y Asistencias (4), Corporativos y Administración (3).
Requisitos:
  Ejecutar previamente DDL (00_ddl), DML (01_dml) y funciones (03_funciones).
  Los triggers (05_triggers) se crean DESPUÉS de este archivo; varios
  procedimientos se apoyan en ellos al ejecutarse (fecha de vencimiento,
  factura automática al pagar, validación de accesos).
Convenciones del módulo:
  * IVA del 19 %. Los precios de ventas y detalles son SIN IVA.
  * fecha_fin de una suscripción es exclusiva: la membresía cubre
    fecha_inicio <= día < fecha_fin.
  * Los procedimientos no abren transacciones propias, para poder
    llamarse unos a otros y desde scripts de prueba con ROLLBACK.
    Todos validan los datos antes de escribir. Para atomicidad total,
    llamar dentro de START TRANSACTION ... COMMIT.
  * Los procedimientos usan NOW()/CURDATE(), por lo que respetan
    SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00') para probar
    con la fecha de referencia de los datos.
*/
USE coworking_grupo5;

DELIMITER $$

-- =====================================================================
--  MÓDULO MEMBRESÍAS (4)
-- =====================================================================

-- =========================================
-- PROCEDIMIENTO 01: sp_registrar_membresia
-- Registra una nueva membresía (suscripción) para un usuario.
--   * Si p_fecha_inicio es NULL, la membresía se ACUMULA: empieza hoy o
--     cuando termine la última membresía vigente/pendiente del usuario.
--   * La fecha de vencimiento la calcula el trigger
--     trg_suscripciones_bi_fecha_vencimiento según el tipo.
--   * Estado inicial: PENDIENTE (pasa a ACTIVA con el pago).
--   * Genera la venta y su detalle (concepto MEMBRESIA). Las CORPORATIVAS
--     no generan venta individual: se cobran en la factura consolidada
--     de la empresa (sp_generar_factura_empresa).
-- Ejemplo: CALL sp_registrar_membresia(59, 'MENSUAL', NULL, @id);
-- =========================================
DROP PROCEDURE IF EXISTS sp_registrar_membresia $$
CREATE PROCEDURE sp_registrar_membresia(
    IN  p_id_usuario     INT,
    IN  p_tipo           VARCHAR(20),
    IN  p_fecha_inicio   DATE,
    OUT p_id_suscripcion INT)
BEGIN
    DECLARE v_id_membresia INT;
    DECLARE v_precio       DECIMAL(10,2);
    DECLARE v_inicio       DATE;
    DECLARE v_id_venta     INT;

    IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    SELECT id_membresia, precio INTO v_id_membresia, v_precio
      FROM membresias
     WHERE tipo_membresia = UPPER(p_tipo);

    IF v_id_membresia IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Tipo de membresia invalido (DIARIA, MENSUAL, CORPORATIVA o PREMIUM)';
    END IF;

    IF UPPER(p_tipo) = 'CORPORATIVA' AND NOT EXISTS (
           SELECT 1 FROM empleados_empresa ee
             JOIN usuarios u ON u.id_persona = ee.id_persona
            WHERE u.id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La membresia CORPORATIVA requiere que el usuario sea empleado de una empresa';
    END IF;

    -- Membresías acumulables: si no se indica fecha, empieza al final de la última vigente
    SET v_inicio = COALESCE(p_fecha_inicio,
                   GREATEST(CURDATE(),
                            COALESCE((SELECT MAX(fecha_fin) FROM suscripciones
                                       WHERE id_usuario = p_id_usuario
                                         AND estado IN ('ACTIVA', 'PENDIENTE')
                                         AND fecha_fin > CURDATE()), CURDATE())));

    -- fecha_fin provisional: el trigger la reemplaza por la real
    INSERT INTO suscripciones (id_usuario, id_membresia, fecha_inicio, fecha_fin, estado)
    VALUES (p_id_usuario, v_id_membresia, v_inicio, DATE_ADD(v_inicio, INTERVAL 1 DAY), 'PENDIENTE');
    SET p_id_suscripcion = LAST_INSERT_ID();

    IF UPPER(p_tipo) <> 'CORPORATIVA' THEN
        INSERT INTO ventas (id_usuario, total) VALUES (p_id_usuario, v_precio);
        SET v_id_venta = LAST_INSERT_ID();
        INSERT INTO detalles_venta (id_venta, id_suscripcion, concepto, precio)
        VALUES (v_id_venta, p_id_suscripcion, 'MEMBRESIA', v_precio);
    END IF;

    SELECT s.id_suscripcion, s.id_usuario, m.tipo_membresia, s.fecha_inicio,
           s.fecha_fin, s.estado, v_id_venta AS id_venta, m.precio AS precio_sin_iva
      FROM suscripciones s
      JOIN membresias m ON m.id_membresia = s.id_membresia
     WHERE s.id_suscripcion = p_id_suscripcion;
END $$

-- =========================================
-- PROCEDIMIENTO 02: sp_renovar_membresia
-- Renueva la membresía del usuario con el MISMO tipo que tenía.
-- La nueva vigencia empieza donde termina la actual (si sigue vigente)
-- o hoy (si ya venció), de modo que nunca se pierden días pagados.
-- No permite renovar si la última membresía está SUSPENDIDA (deuda).
-- Ejemplo: CALL sp_renovar_membresia(44, @id);
-- =========================================
DROP PROCEDURE IF EXISTS sp_renovar_membresia $$
CREATE PROCEDURE sp_renovar_membresia(
    IN  p_id_usuario     INT,
    OUT p_id_suscripcion INT)
BEGIN
    DECLARE v_tipo   VARCHAR(20);
    DECLARE v_fin    DATE;
    DECLARE v_estado VARCHAR(20);

    SELECT m.tipo_membresia, s.fecha_fin, s.estado
      INTO v_tipo, v_fin, v_estado
      FROM suscripciones s
      JOIN membresias m ON m.id_membresia = s.id_membresia
     WHERE s.id_usuario = p_id_usuario
     ORDER BY s.fecha_fin DESC, s.id_suscripcion DESC
     LIMIT 1;

    IF v_tipo IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El usuario no tiene membresias previas; use sp_registrar_membresia';
    END IF;
    IF v_estado = 'SUSPENDIDA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede renovar: la membresia esta suspendida por falta de pago';
    END IF;

    CALL sp_registrar_membresia(p_id_usuario, v_tipo, GREATEST(v_fin, CURDATE()), p_id_suscripcion);
END $$

-- =========================================
-- PROCEDIMIENTO 03: sp_actualizar_membresias_vencidas
-- Marca como VENCIDA toda suscripción ACTIVA cuya fecha_fin ya pasó
-- (fecha_fin <= hoy, porque fecha_fin es exclusiva).
-- Ejemplo: CALL sp_actualizar_membresias_vencidas(@n); SELECT @n;
-- =========================================
DROP PROCEDURE IF EXISTS sp_actualizar_membresias_vencidas $$
CREATE PROCEDURE sp_actualizar_membresias_vencidas(OUT p_actualizadas INT)
BEGIN
    UPDATE suscripciones
       SET estado = 'VENCIDA'
     WHERE estado = 'ACTIVA'
       AND fecha_fin <= CURDATE();
    SET p_actualizadas = ROW_COUNT();

    SELECT p_actualizadas AS membresias_marcadas_vencidas;
END $$

-- =========================================
-- PROCEDIMIENTO 04: sp_suspender_membresias_morosas
-- Suspende las membresías vigentes (ACTIVA o PENDIENTE) de los usuarios
-- con facturas PENDIENTES vencidas hace más de p_dias días.
--   * Deuda propia del usuario       -> se suspenden sus membresías.
--   * Deuda de la empresa (corporativa) -> se suspenden las membresías
--     CORPORATIVAS de todos sus empleados.
-- Notifica a recepción la cantidad suspendida.
-- Ejemplo: CALL sp_suspender_membresias_morosas(10, @n);
-- =========================================
DROP PROCEDURE IF EXISTS sp_suspender_membresias_morosas $$
CREATE PROCEDURE sp_suspender_membresias_morosas(
    IN  p_dias        INT,
    OUT p_suspendidas INT)
BEGIN
    DECLARE v_propias INT DEFAULT 0;

    IF p_dias IS NULL OR p_dias < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_dias debe ser un numero mayor o igual a 0';
    END IF;

    -- Deudas propias del usuario
    UPDATE suscripciones s
       SET s.estado = 'SUSPENDIDA'
     WHERE s.estado IN ('ACTIVA', 'PENDIENTE')
       AND s.fecha_fin > CURDATE()
       AND s.id_usuario IN (
             SELECT v.id_usuario
               FROM ventas v
               JOIN facturas f ON f.id_venta = v.id_venta
              WHERE v.id_usuario IS NOT NULL
                AND f.estado = 'PENDIENTE'
                AND f.saldo_pendiente > 0
                AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias DAY));
    SET v_propias = ROW_COUNT();

    -- Deudas de la empresa: membresías corporativas de sus empleados
    UPDATE suscripciones s
      JOIN membresias m         ON m.id_membresia = s.id_membresia
                               AND m.tipo_membresia = 'CORPORATIVA'
      JOIN usuarios u           ON u.id_usuario = s.id_usuario
      JOIN empleados_empresa ee ON ee.id_persona = u.id_persona
       SET s.estado = 'SUSPENDIDA'
     WHERE s.estado IN ('ACTIVA', 'PENDIENTE')
       AND s.fecha_fin > CURDATE()
       AND ee.id_empresa IN (
             SELECT v.id_empresa
               FROM ventas v
               JOIN facturas f ON f.id_venta = v.id_venta
              WHERE v.id_empresa IS NOT NULL
                AND f.estado = 'PENDIENTE'
                AND f.saldo_pendiente > 0
                AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias DAY));
    SET p_suspendidas = v_propias + ROW_COUNT();

    IF p_suspendidas > 0 THEN
        INSERT INTO notificaciones (destinatario, tipo, mensaje)
        VALUES ('RECEPCION', 'MEMBRESIA_SUSPENDIDA',
                CONCAT(p_suspendidas, ' membresias suspendidas por facturas vencidas hace mas de ',
                       p_dias, ' dias.'));
    END IF;

    SELECT p_suspendidas AS membresias_suspendidas;
END $$

-- =====================================================================
--  MÓDULO RESERVAS Y ESPACIOS (5)
-- =====================================================================

-- =========================================
-- PROCEDIMIENTO 05: sp_verificar_disponibilidad
-- Comprueba si un espacio puede reservarse en un horario:
--   1. El espacio existe y está DISPONIBLE.
--   2. El horario es válido, futuro y dentro de un mismo día.
--   3. La sede está abierta ese día y el horario cabe en su atención.
--   4. No se solapa con otra reserva no cancelada del mismo espacio.
-- Devuelve p_disponible (TRUE/FALSE) y el motivo.
-- Ejemplo:
--   CALL sp_verificar_disponibilidad(5, '2026-10-20 09:00', '2026-10-20 11:00', @ok, @motivo);
-- =========================================
DROP PROCEDURE IF EXISTS sp_verificar_disponibilidad $$
CREATE PROCEDURE sp_verificar_disponibilidad(
    IN  p_id_espacio  INT,
    IN  p_inicio      DATETIME,
    IN  p_fin         DATETIME,
    OUT p_disponible  BOOLEAN,
    OUT p_motivo      VARCHAR(150))
BEGIN
    DECLARE v_estado  VARCHAR(20);
    DECLARE v_sede    INT;
    DECLARE v_abre    TIME;
    DECLARE v_cierra  TIME;
    DECLARE v_dia     VARCHAR(10);

    SET p_disponible = FALSE;

    SELECT estado, id_sede_coworking INTO v_estado, v_sede
      FROM espacios WHERE id_espacio = p_id_espacio;

    SET v_dia = ELT(WEEKDAY(p_inicio) + 1,
                    'LUNES','MARTES','MIERCOLES','JUEVES','VIERNES','SABADO','DOMINGO');
    SELECT hora_inicio, hora_fin INTO v_abre, v_cierra
      FROM horarios_atencion
     WHERE id_sede_coworking = v_sede AND dia_semana = v_dia;

    IF v_estado IS NULL THEN
        SET p_motivo = 'El espacio no existe';
    ELSEIF v_estado <> 'DISPONIBLE' THEN
        SET p_motivo = CONCAT('El espacio no esta disponible (', v_estado, ')');
    ELSEIF p_inicio IS NULL OR p_fin IS NULL OR p_fin <= p_inicio THEN
        SET p_motivo = 'Horario invalido: la hora de fin debe ser mayor que la de inicio';
    ELSEIF p_inicio < NOW() THEN
        SET p_motivo = 'No se puede reservar en una fecha u hora pasada';
    ELSEIF DATE(p_inicio) <> DATE(p_fin) THEN
        SET p_motivo = 'La reserva debe empezar y terminar el mismo dia';
    ELSEIF v_abre IS NULL THEN
        SET p_motivo = CONCAT('La sede no abre los dias ', v_dia);
    ELSEIF TIME(p_inicio) < v_abre OR TIME(p_fin) > v_cierra THEN
        SET p_motivo = CONCAT('Fuera del horario de atencion (', TIME_FORMAT(v_abre, '%H:%i'),
                              ' a ', TIME_FORMAT(v_cierra, '%H:%i'), ')');
    ELSEIF EXISTS (SELECT 1 FROM reservas
                    WHERE id_espacio   = p_id_espacio
                      AND estado      <> 'CANCELADA'
                      AND fecha_inicio < p_fin
                      AND fecha_fin    > p_inicio) THEN
        SET p_motivo = 'El espacio ya esta reservado en ese horario';
    ELSE
        SET p_disponible = TRUE;
        SET p_motivo     = 'Disponible';
    END IF;
END $$

-- =========================================
-- PROCEDIMIENTO 06: sp_crear_reserva
-- Crea una reserva en estado PENDIENTE y la vincula a usuario y espacio.
--   * Valida disponibilidad (sp_verificar_disponibilidad) y capacidad.
--   * Usuario individual: genera la venta con el detalle RESERVA
--     (precio_hora x horas). Queda PENDIENTE hasta el pago.
--   * Usuario con membresía CORPORATIVA activa: se confirma con el
--     crédito de la empresa y se cobra en la factura consolidada.
-- Ejemplo:
--   CALL sp_crear_reserva(56, 5, '2026-10-20 09:00', '2026-10-20 11:00', 4, @id);
-- =========================================
DROP PROCEDURE IF EXISTS sp_crear_reserva $$
CREATE PROCEDURE sp_crear_reserva(
    IN  p_id_usuario INT,
    IN  p_id_espacio INT,
    IN  p_inicio     DATETIME,
    IN  p_fin        DATETIME,
    IN  p_personas   INT,
    OUT p_id_reserva INT)
BEGIN
    DECLARE v_ok         BOOLEAN;
    DECLARE v_motivo     VARCHAR(150);
    DECLARE v_capacidad  INT;
    DECLARE v_precio     DECIMAL(10,2);
    DECLARE v_corp       INT DEFAULT 0;
    DECLARE v_id_venta   INT;

    IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    CALL sp_verificar_disponibilidad(p_id_espacio, p_inicio, p_fin, v_ok, v_motivo);
    IF NOT v_ok THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_motivo;
    END IF;

    SELECT capacidad,
           ROUND(precio_hora * TIMESTAMPDIFF(MINUTE, p_inicio, p_fin) / 60, 2)
      INTO v_capacidad, v_precio
      FROM espacios WHERE id_espacio = p_id_espacio;

    IF p_personas IS NULL OR p_personas < 1 OR p_personas > v_capacidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cantidad de personas invalida o superior a la capacidad del espacio';
    END IF;

    -- ¿Tiene membresía CORPORATIVA vigente ese día?
    SELECT COUNT(*) INTO v_corp
      FROM suscripciones s
      JOIN membresias m ON m.id_membresia = s.id_membresia
     WHERE s.id_usuario = p_id_usuario
       AND m.tipo_membresia = 'CORPORATIVA'
       AND s.estado = 'ACTIVA'
       AND DATE(p_inicio) >= s.fecha_inicio
       AND DATE(p_inicio) <  s.fecha_fin;

    -- El trigger trg_reservas_bi_estado_pendiente la deja en PENDIENTE
    INSERT INTO reservas (id_espacio, id_usuario, fecha_inicio, fecha_fin, cantidad_personas)
    VALUES (p_id_espacio, p_id_usuario, p_inicio, p_fin, p_personas);
    SET p_id_reserva = LAST_INSERT_ID();

    IF v_corp > 0 THEN
        UPDATE reservas SET estado = 'CONFIRMADA' WHERE id_reserva = p_id_reserva;
    ELSE
        INSERT INTO ventas (id_usuario, total) VALUES (p_id_usuario, v_precio);
        SET v_id_venta = LAST_INSERT_ID();
        INSERT INTO detalles_venta (id_venta, id_reserva, concepto, precio)
        VALUES (v_id_venta, p_id_reserva, 'RESERVA', v_precio);
    END IF;

    SELECT r.id_reserva, r.id_usuario, e.nombre AS espacio, r.fecha_inicio, r.fecha_fin,
           r.cantidad_personas, r.estado, v_id_venta AS id_venta,
           v_precio AS precio_sin_iva, ROUND(v_precio * 1.19, 2) AS precio_con_iva,
           IF(v_corp > 0, 'Facturacion consolidada de la empresa', 'Pendiente de pago') AS cobro
      FROM reservas r JOIN espacios e ON e.id_espacio = r.id_espacio
     WHERE r.id_reserva = p_id_reserva;
END $$

-- =========================================
-- PROCEDIMIENTO 07: sp_confirmar_reserva_pago
-- Registra el pago (PAGADO) de una reserva PENDIENTE por el saldo
-- total con IVA. Los triggers del módulo de pagos crean la factura,
-- actualizan el saldo, la marcan PAGADA y confirman la reserva.
-- Ejemplo: CALL sp_confirmar_reserva_pago(@id_reserva, 2, @id_pago);
--          (2 = Tarjeta; ver tabla metodos_pago)
-- =========================================
DROP PROCEDURE IF EXISTS sp_confirmar_reserva_pago $$
CREATE PROCEDURE sp_confirmar_reserva_pago(
    IN  p_id_reserva     INT,
    IN  p_id_metodo_pago INT,
    OUT p_id_pago        INT)
BEGIN
    DECLARE v_estado    VARCHAR(20);
    DECLARE v_id_venta  INT;
    DECLARE v_monto     DECIMAL(10,2);
    DECLARE v_pagado    DECIMAL(10,2);

    SELECT estado INTO v_estado FROM reservas WHERE id_reserva = p_id_reserva;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe';
    ELSEIF v_estado <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo se pueden confirmar reservas en estado PENDIENTE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM metodos_pago WHERE id_metodo_pago = p_id_metodo_pago) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Metodo de pago invalido';
    END IF;

    SELECT MAX(id_venta) INTO v_id_venta
      FROM detalles_venta
     WHERE id_reserva = p_id_reserva AND concepto = 'RESERVA';

    -- Reserva sin venta (p. ej. creada fuera de sp_crear_reserva): se crea la venta
    IF v_id_venta IS NULL THEN
        INSERT INTO ventas (id_usuario, total)
        SELECT r.id_usuario, ROUND(e.precio_hora * TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin) / 60, 2)
          FROM reservas r JOIN espacios e ON e.id_espacio = r.id_espacio
         WHERE r.id_reserva = p_id_reserva;
        SET v_id_venta = LAST_INSERT_ID();
        INSERT INTO detalles_venta (id_venta, id_reserva, concepto, precio)
        SELECT v_id_venta, p_id_reserva, 'RESERVA', total FROM ventas WHERE id_venta = v_id_venta;
    END IF;

    -- Monto = saldo de la factura si existe; si no, total de la venta + IVA
    SELECT COALESCE(SUM(monto), 0) INTO v_pagado
      FROM pagos WHERE id_venta = v_id_venta AND estado = 'PAGADO';
    SET v_monto = COALESCE((SELECT saldo_pendiente FROM facturas WHERE id_venta = v_id_venta),
                           (SELECT ROUND(total * 1.19, 2) FROM ventas WHERE id_venta = v_id_venta) - v_pagado);

    IF v_monto <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta de esta reserva no tiene saldo pendiente';
    END IF;

    INSERT INTO pagos (id_venta, id_metodo_pago, monto, estado)
    VALUES (v_id_venta, p_id_metodo_pago, v_monto, 'PAGADO');
    SET p_id_pago = LAST_INSERT_ID();

    SELECT r.id_reserva, r.estado AS estado_reserva, p.id_pago, p.monto,
           f.numero_factura, f.estado AS estado_factura, f.saldo_pendiente
      FROM reservas r
      JOIN pagos p          ON p.id_pago = p_id_pago
      LEFT JOIN facturas f  ON f.id_venta = p.id_venta
     WHERE r.id_reserva = p_id_reserva;
END $$

-- =========================================
-- PROCEDIMIENTO 08: sp_cancelar_reserva
-- Cancela una reserva PENDIENTE o CONFIRMADA y genera el reembolso si aplica.
--   p_porcentaje_reembolso: 0-100. Si es NULL se aplica la política:
--     * 48 horas o más antes del inicio -> 100 %
--     * menos de 48 horas               ->  50 %
--     * la reserva ya empezó            ->   0 %
--   * Pagos PENDIENTES de la venta -> CANCELADO (se registran en el log).
--   * Si no se había pagado nada, la factura (si existe) queda ANULADA.
--   * El log de la cancelación lo deja trg_reservas_au_log_cancelacion.
-- Ejemplo: CALL sp_cancelar_reserva(513, NULL, @reembolso); SELECT @reembolso;
-- =========================================
DROP PROCEDURE IF EXISTS sp_cancelar_reserva $$
CREATE PROCEDURE sp_cancelar_reserva(
    IN  p_id_reserva            INT,
    IN  p_porcentaje_reembolso  DECIMAL(5,2),
    OUT p_monto_reembolso       DECIMAL(10,2))
BEGIN
    DECLARE v_estado     VARCHAR(20);
    DECLARE v_inicio     DATETIME;
    DECLARE v_pct        DECIMAL(5,2);
    DECLARE v_id_venta   INT;
    DECLARE v_valor      DECIMAL(10,2);
    DECLARE v_pagado     DECIMAL(10,2) DEFAULT 0;
    DECLARE v_id_pago    INT;

    SET p_monto_reembolso = 0;

    SELECT estado, fecha_inicio INTO v_estado, v_inicio
      FROM reservas WHERE id_reserva = p_id_reserva;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe';
    ELSEIF v_estado NOT IN ('PENDIENTE', 'CONFIRMADA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo se pueden cancelar reservas PENDIENTES o CONFIRMADAS';
    END IF;
    IF p_porcentaje_reembolso IS NOT NULL
       AND (p_porcentaje_reembolso < 0 OR p_porcentaje_reembolso > 100) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje de reembolso debe estar entre 0 y 100';
    END IF;

    SET v_pct = COALESCE(p_porcentaje_reembolso,
                CASE WHEN v_inicio >= NOW() + INTERVAL 48 HOUR THEN 100
                     WHEN v_inicio >  NOW()                    THEN 50
                     ELSE 0 END);

    UPDATE reservas SET estado = 'CANCELADA' WHERE id_reserva = p_id_reserva;

    SELECT MAX(id_venta) INTO v_id_venta
      FROM detalles_venta WHERE id_reserva = p_id_reserva AND concepto = 'RESERVA';

    IF v_id_venta IS NOT NULL THEN
        -- Pagos sin confirmar: se anulan
        UPDATE pagos SET estado = 'CANCELADO'
         WHERE id_venta = v_id_venta AND estado = 'PENDIENTE';

        SELECT COALESCE(SUM(monto), 0), MAX(id_pago) INTO v_pagado, v_id_pago
          FROM pagos WHERE id_venta = v_id_venta AND estado = 'PAGADO';

        IF v_pagado > 0 THEN
            -- Se reembolsa sobre lo pagado por esta reserva (con IVA)
            SELECT ROUND(precio * 1.19, 2) INTO v_valor
              FROM detalles_venta
             WHERE id_venta = v_id_venta AND id_reserva = p_id_reserva AND concepto = 'RESERVA'
             LIMIT 1;
            SET p_monto_reembolso = ROUND(LEAST(v_pagado, v_valor) * v_pct / 100, 2);

            IF p_monto_reembolso > 0 THEN
                INSERT INTO reembolsos (id_pago, id_reserva, monto, motivo)
                VALUES (v_id_pago, p_id_reserva, p_monto_reembolso,
                        CONCAT('Cancelacion de la reserva: reembolso del ', ROUND(v_pct), '%'));
            END IF;
        ELSE
            UPDATE facturas
               SET estado = 'ANULADA',
                   saldo_pendiente = 0,
                   motivo_anulacion = 'Reserva cancelada antes de confirmar el pago'
             WHERE id_venta = v_id_venta AND estado = 'PENDIENTE';
        END IF;
    END IF;

    SELECT p_id_reserva AS id_reserva, 'CANCELADA' AS estado,
           v_pagado AS valor_pagado,
           IF(v_pagado > 0, v_pct, 0) AS porcentaje_reembolso,
           p_monto_reembolso AS monto_reembolso;
END $$

-- =========================================
-- PROCEDIMIENTO 09: sp_liberar_reservas_no_confirmadas
-- Recorre (cursor) las reservas PENDIENTES creadas hace más de p_horas
-- horas sin pago y las cancela con sp_cancelar_reserva (sin reembolso,
-- porque no se pagaron).
-- Ejemplo: CALL sp_liberar_reservas_no_confirmadas(2, @n);
-- =========================================
DROP PROCEDURE IF EXISTS sp_liberar_reservas_no_confirmadas $$
CREATE PROCEDURE sp_liberar_reservas_no_confirmadas(
    IN  p_horas      INT,
    OUT p_canceladas INT)
BEGIN
    DECLARE v_id      INT;
    DECLARE v_fin     BOOLEAN DEFAULT FALSE;
    DECLARE v_monto   DECIMAL(10,2);
    DECLARE cur_pendientes CURSOR FOR
        SELECT id_reserva FROM reservas
         WHERE estado = 'PENDIENTE'
           AND fecha_creacion <= NOW() - INTERVAL p_horas HOUR;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = TRUE;

    IF p_horas IS NULL OR p_horas < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_horas debe ser mayor o igual a 0';
    END IF;

    SET p_canceladas = 0;
    OPEN cur_pendientes;
    recorrer: LOOP
        FETCH cur_pendientes INTO v_id;
        IF v_fin THEN LEAVE recorrer; END IF;
        CALL sp_cancelar_reserva(v_id, 0, v_monto);
        SET p_canceladas = p_canceladas + 1;
    END LOOP;
    CLOSE cur_pendientes;

    SELECT p_canceladas AS reservas_liberadas;
END $$

-- =====================================================================
--  MÓDULO PAGOS Y FACTURACIÓN (4)
-- =====================================================================

-- =========================================
-- PROCEDIMIENTO 10: sp_generar_factura_membresia
-- Crea la factura de una membresía al activarla o renovarla.
--   * Si la membresía no tiene venta, la crea (detalle MEMBRESIA).
--   * Si la venta ya tiene factura, devuelve la existente (no duplica).
--   * Vence a los 15 días; el saldo descuenta lo ya pagado.
-- Las CORPORATIVAS se facturan con sp_generar_factura_empresa.
-- Ejemplo: CALL sp_generar_factura_membresia(@id_suscripcion, @id_factura);
-- =========================================
DROP PROCEDURE IF EXISTS sp_generar_factura_membresia $$
CREATE PROCEDURE sp_generar_factura_membresia(
    IN  p_id_suscripcion INT,
    OUT p_id_factura     INT)
BEGIN
    DECLARE v_id_usuario INT;
    DECLARE v_tipo       VARCHAR(20);
    DECLARE v_precio     DECIMAL(10,2);
    DECLARE v_id_venta   INT;
    DECLARE v_subtotal   DECIMAL(10,2);
    DECLARE v_iva        DECIMAL(10,2);
    DECLARE v_pagado     DECIMAL(10,2);

    SELECT s.id_usuario, m.tipo_membresia, m.precio
      INTO v_id_usuario, v_tipo, v_precio
      FROM suscripciones s JOIN membresias m ON m.id_membresia = s.id_membresia
     WHERE s.id_suscripcion = p_id_suscripcion;

    IF v_id_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La suscripcion no existe';
    END IF;

    SELECT id_venta INTO v_id_venta
      FROM detalles_venta WHERE id_suscripcion = p_id_suscripcion;

    IF v_id_venta IS NULL THEN
        IF v_tipo = 'CORPORATIVA' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Las membresias CORPORATIVAS se facturan con sp_generar_factura_empresa';
        END IF;
        INSERT INTO ventas (id_usuario, total) VALUES (v_id_usuario, v_precio);
        SET v_id_venta = LAST_INSERT_ID();
        INSERT INTO detalles_venta (id_venta, id_suscripcion, concepto, precio)
        VALUES (v_id_venta, p_id_suscripcion, 'MEMBRESIA', v_precio);
    END IF;

    SELECT id_factura INTO p_id_factura FROM facturas WHERE id_venta = v_id_venta;

    IF p_id_factura IS NULL THEN
        SELECT total INTO v_subtotal FROM ventas WHERE id_venta = v_id_venta;
        SET v_iva = ROUND(v_subtotal * 0.19, 2);
        SELECT COALESCE(SUM(monto), 0) INTO v_pagado
          FROM pagos WHERE id_venta = v_id_venta AND estado = 'PAGADO';

        INSERT INTO facturas (id_venta, numero_factura, fecha_emision, fecha_vencimiento,
                              subtotal, iva, recargo, total, saldo_pendiente, estado)
        VALUES (v_id_venta,
                CONCAT('FV-', LPAD((SELECT COALESCE(MAX(f.id_factura), 0) + 1 FROM facturas f), 6, '0')),
                CURDATE(), DATE_ADD(CURDATE(), INTERVAL 15 DAY),
                v_subtotal, v_iva, 0, v_subtotal + v_iva,
                GREATEST(v_subtotal + v_iva - v_pagado, 0),
                IF(v_subtotal + v_iva - v_pagado <= 0, 'PAGADA', 'PENDIENTE'));
        SET p_id_factura = LAST_INSERT_ID();
    END IF;

    SELECT id_factura, numero_factura, id_venta, fecha_emision, fecha_vencimiento,
           subtotal, iva, total, saldo_pendiente, estado
      FROM facturas WHERE id_factura = p_id_factura;
END $$

-- =========================================
-- PROCEDIMIENTO 11: sp_generar_factura_empresa
-- Genera UNA factura consolidada para la empresa con todos los cargos
-- aún no facturados de sus empleados en el mes indicado:
--   * Membresías CORPORATIVAS que empiezan en el mes.
--   * Reservas CONFIRMADAS/FINALIZADAS (concepto RESERVA) y NO_SHOW
--     (concepto PENALIZACION, 20 % del valor de la reserva).
--   * Servicios adicionales consumidos.
-- Un cargo ya incluido en cualquier venta no se vuelve a facturar.
-- Ejemplo: CALL sp_generar_factura_empresa(1, 2026, 10, @id_factura);
-- =========================================
DROP PROCEDURE IF EXISTS sp_generar_factura_empresa $$
CREATE PROCEDURE sp_generar_factura_empresa(
    IN  p_id_empresa INT,
    IN  p_anio       INT,
    IN  p_mes        INT,
    OUT p_id_factura INT)
BEGIN
    DECLARE v_desde     DATE;
    DECLARE v_hasta     DATE;
    DECLARE v_id_venta  INT;
    DECLARE v_subtotal  DECIMAL(10,2);
    DECLARE v_iva       DECIMAL(10,2);

    IF NOT EXISTS (SELECT 1 FROM empresas WHERE id_empresa = p_id_empresa) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no existe';
    END IF;
    IF p_mes NOT BETWEEN 1 AND 12 OR p_anio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Periodo invalido';
    END IF;

    SET v_desde = MAKEDATE(p_anio, 1) + INTERVAL (p_mes - 1) MONTH;
    SET v_hasta = v_desde + INTERVAL 1 MONTH;

    -- Cargos pendientes de facturar (tabla temporal de trabajo)
    DROP TEMPORARY TABLE IF EXISTS tmp_cargos_empresa;
    CREATE TEMPORARY TABLE tmp_cargos_empresa (
        id_suscripcion      INT NULL,
        id_reserva          INT NULL,
        id_servicio_usuario INT NULL,
        concepto            VARCHAR(20) NOT NULL,
        precio              DECIMAL(10,2) NOT NULL
    );

    INSERT INTO tmp_cargos_empresa (id_suscripcion, concepto, precio)
    SELECT s.id_suscripcion, 'MEMBRESIA', m.precio
      FROM suscripciones s
      JOIN membresias m         ON m.id_membresia = s.id_membresia
      JOIN usuarios u           ON u.id_usuario = s.id_usuario
      JOIN empleados_empresa ee ON ee.id_persona = u.id_persona AND ee.id_empresa = p_id_empresa
     WHERE m.tipo_membresia = 'CORPORATIVA'
       AND s.fecha_inicio >= v_desde AND s.fecha_inicio < v_hasta
       AND NOT EXISTS (SELECT 1 FROM detalles_venta d WHERE d.id_suscripcion = s.id_suscripcion);

    INSERT INTO tmp_cargos_empresa (id_reserva, concepto, precio)
    SELECT r.id_reserva,
           IF(r.estado = 'NO_SHOW', 'PENALIZACION', 'RESERVA'),
           ROUND(e.precio_hora * TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin) / 60
                 * IF(r.estado = 'NO_SHOW', 0.20, 1), 2)
      FROM reservas r
      JOIN espacios e           ON e.id_espacio = r.id_espacio
      JOIN usuarios u           ON u.id_usuario = r.id_usuario
      JOIN empleados_empresa ee ON ee.id_persona = u.id_persona AND ee.id_empresa = p_id_empresa
     WHERE r.estado IN ('CONFIRMADA', 'FINALIZADA', 'NO_SHOW')
       AND r.fecha_inicio >= v_desde AND r.fecha_inicio < v_hasta
       AND NOT EXISTS (SELECT 1 FROM detalles_venta d
                        WHERE d.id_reserva = r.id_reserva
                          AND d.concepto IN ('RESERVA', 'PENALIZACION'));

    INSERT INTO tmp_cargos_empresa (id_servicio_usuario, concepto, precio)
    SELECT su.id_servicio_usuario, 'SERVICIO', ROUND(sv.precio * su.cantidad, 2)
      FROM servicio_usuario su
      JOIN servicios sv         ON sv.id_servicio = su.id_servicio
      JOIN usuarios u           ON u.id_usuario = su.id_usuario
      JOIN empleados_empresa ee ON ee.id_persona = u.id_persona AND ee.id_empresa = p_id_empresa
     WHERE su.fecha >= v_desde AND su.fecha < v_hasta
       AND NOT EXISTS (SELECT 1 FROM detalles_venta d
                        WHERE d.id_servicio_usuario = su.id_servicio_usuario);

    IF (SELECT COUNT(*) FROM tmp_cargos_empresa) = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_cargos_empresa;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La empresa no tiene cargos pendientes de facturar en ese periodo';
    END IF;

    SELECT SUM(precio) INTO v_subtotal FROM tmp_cargos_empresa;
    SET v_iva = ROUND(v_subtotal * 0.19, 2);

    INSERT INTO ventas (id_empresa, total) VALUES (p_id_empresa, v_subtotal);
    SET v_id_venta = LAST_INSERT_ID();

    INSERT INTO detalles_venta (id_venta, id_suscripcion, id_reserva, id_servicio_usuario, concepto, precio)
    SELECT v_id_venta, id_suscripcion, id_reserva, id_servicio_usuario, concepto, precio
      FROM tmp_cargos_empresa;

    INSERT INTO facturas (id_venta, numero_factura, fecha_emision, fecha_vencimiento,
                          subtotal, iva, recargo, total, saldo_pendiente, estado)
    VALUES (v_id_venta,
            CONCAT('FV-', LPAD((SELECT COALESCE(MAX(f.id_factura), 0) + 1 FROM facturas f), 6, '0')),
            CURDATE(), DATE_ADD(CURDATE(), INTERVAL 15 DAY),
            v_subtotal, v_iva, 0, v_subtotal + v_iva, v_subtotal + v_iva, 'PENDIENTE');
    SET p_id_factura = LAST_INSERT_ID();

    SELECT f.numero_factura, e.razon_social, f.fecha_emision, f.fecha_vencimiento,
           (SELECT COUNT(*) FROM tmp_cargos_empresa) AS cargos,
           f.subtotal, f.iva, f.total
      FROM facturas f
      JOIN ventas v   ON v.id_venta = f.id_venta
      JOIN empresas e ON e.id_empresa = v.id_empresa
     WHERE f.id_factura = p_id_factura;

    SELECT concepto, COUNT(*) AS cantidad, SUM(precio) AS subtotal
      FROM tmp_cargos_empresa GROUP BY concepto;

    DROP TEMPORARY TABLE IF EXISTS tmp_cargos_empresa;
END $$

-- =========================================
-- PROCEDIMIENTO 12: sp_aplicar_recargos
-- Aplica un recargo (p_porcentaje % del subtotal) a las facturas
-- PENDIENTES vencidas hace más de p_dias días que aún no lo tienen.
-- Aumenta total y saldo pendiente. Al modificar la factura, el trigger
-- trg_facturas_au_suspender_membresia suspende la membresía asociada.
-- Ejemplo: CALL sp_aplicar_recargos(15, 5, @n);
-- =========================================
DROP PROCEDURE IF EXISTS sp_aplicar_recargos $$
CREATE PROCEDURE sp_aplicar_recargos(
    IN  p_dias       INT,
    IN  p_porcentaje DECIMAL(5,2),
    OUT p_facturas   INT)
BEGIN
    IF p_dias IS NULL OR p_dias < 0 OR p_porcentaje IS NULL OR p_porcentaje <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Parametros invalidos para el recargo';
    END IF;

    -- MySQL asigna de izquierda a derecha: total y saldo usan el recargo nuevo
    UPDATE facturas
       SET recargo         = ROUND(subtotal * p_porcentaje / 100, 2),
           total           = subtotal + iva + recargo,
           saldo_pendiente = saldo_pendiente + recargo
     WHERE estado  = 'PENDIENTE'
       AND recargo = 0
       AND saldo_pendiente > 0
       AND fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias DAY);
    SET p_facturas = ROW_COUNT();

    SELECT p_facturas AS facturas_con_recargo;
END $$

-- =========================================
-- PROCEDIMIENTO 13: sp_bloquear_servicios_morosos
-- Bloquea los servicios adicionales (usuarios.servicios_bloqueados) de
-- quienes tienen facturas PENDIENTES vencidas hace más de p_dias_gracia
-- días (deuda propia o de su empresa) y desbloquea a quienes ya no
-- tienen deudas.
-- Ejemplo: CALL sp_bloquear_servicios_morosos(10, @b, @d);
-- =========================================
DROP PROCEDURE IF EXISTS sp_bloquear_servicios_morosos $$
CREATE PROCEDURE sp_bloquear_servicios_morosos(
    IN  p_dias_gracia    INT,
    OUT p_bloqueados     INT,
    OUT p_desbloqueados  INT)
BEGIN
    IF p_dias_gracia IS NULL OR p_dias_gracia < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_dias_gracia debe ser mayor o igual a 0';
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_morosos;
    CREATE TEMPORARY TABLE tmp_morosos (id_usuario INT PRIMARY KEY);

    INSERT IGNORE INTO tmp_morosos
    SELECT v.id_usuario
      FROM ventas v JOIN facturas f ON f.id_venta = v.id_venta
     WHERE v.id_usuario IS NOT NULL
       AND f.estado = 'PENDIENTE' AND f.saldo_pendiente > 0
       AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias_gracia DAY);

    INSERT IGNORE INTO tmp_morosos
    SELECT u.id_usuario
      FROM ventas v
      JOIN facturas f           ON f.id_venta = v.id_venta
      JOIN empleados_empresa ee ON ee.id_empresa = v.id_empresa
      JOIN usuarios u           ON u.id_persona = ee.id_persona
     WHERE f.estado = 'PENDIENTE' AND f.saldo_pendiente > 0
       AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias_gracia DAY);

    UPDATE usuarios SET servicios_bloqueados = TRUE
     WHERE servicios_bloqueados = FALSE
       AND id_usuario IN (SELECT id_usuario FROM tmp_morosos);
    SET p_bloqueados = ROW_COUNT();

    UPDATE usuarios SET servicios_bloqueados = FALSE
     WHERE servicios_bloqueados = TRUE
       AND id_usuario NOT IN (SELECT id_usuario FROM tmp_morosos);
    SET p_desbloqueados = ROW_COUNT();

    DROP TEMPORARY TABLE IF EXISTS tmp_morosos;

    SELECT p_bloqueados AS usuarios_bloqueados, p_desbloqueados AS usuarios_desbloqueados,
           (SELECT COUNT(*) FROM usuarios WHERE servicios_bloqueados) AS total_bloqueados;
END $$

-- =====================================================================
--  MÓDULO ACCESOS Y ASISTENCIAS (4)
-- =====================================================================

-- =========================================
-- PROCEDIMIENTO 14: sp_registrar_entrada
-- Registra el intento de entrada con el código RFID/QR leído en la sede.
--   * Código inexistente -> DENEGADO / CODIGO_INVALIDO.
--   * En otro caso inserta el acceso y el trigger
--     trg_control_acceso_bi_validar_acceso valida horario, membresía
--     activa o reserva confirmada. Los triggers registran la asistencia,
--     el último acceso y el log de rechazos.
--   * Si queda PERMITIDO y el usuario tenía una entrada abierta ese día,
--     se le asigna la salida automática (un trigger no puede modificar
--     su propia tabla, por eso se hace aquí).
-- Ejemplo: CALL sp_registrar_entrada('QR-123456', 1, 'QR', @id, @res, @motivo);
-- =========================================
DROP PROCEDURE IF EXISTS sp_registrar_entrada $$
CREATE PROCEDURE sp_registrar_entrada(
    IN  p_codigo_acceso VARCHAR(60),
    IN  p_id_sede       INT,
    IN  p_metodo        VARCHAR(4),
    OUT p_id_control    INT,
    OUT p_resultado     VARCHAR(10),
    OUT p_motivo        VARCHAR(30))
BEGIN
    DECLARE v_id_usuario INT;
    DECLARE v_fecha      DATE DEFAULT CURDATE();
    DECLARE v_hora       TIME DEFAULT TIME(DATE_FORMAT(NOW(), '%H:%i:00'));

    IF NOT EXISTS (SELECT 1 FROM sedes_coworking WHERE id_sede_coworking = p_id_sede) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La sede no existe';
    END IF;
    IF UPPER(p_metodo) NOT IN ('RFID', 'QR') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Metodo invalido: use RFID o QR';
    END IF;

    SELECT id_usuario INTO v_id_usuario FROM usuarios WHERE codigo_acceso = p_codigo_acceso;

    IF v_id_usuario IS NULL THEN
        INSERT INTO control_acceso (id_usuario, id_sede_coworking, fecha, hora_entrada,
                                    metodo, resultado, motivo_rechazo)
        VALUES (NULL, p_id_sede, v_fecha, v_hora, UPPER(p_metodo), 'DENEGADO', 'CODIGO_INVALIDO');
    ELSE
        INSERT INTO control_acceso (id_usuario, id_sede_coworking, fecha, hora_entrada,
                                    metodo, resultado)
        VALUES (v_id_usuario, p_id_sede, v_fecha, v_hora, UPPER(p_metodo), 'PERMITIDO');
    END IF;
    SET p_id_control = LAST_INSERT_ID();

    SELECT resultado, motivo_rechazo INTO p_resultado, p_motivo
      FROM control_acceso WHERE id_control = p_id_control;

    -- Salida automática de la entrada anterior que quedó abierta hoy
    IF p_resultado = 'PERMITIDO' THEN
        UPDATE control_acceso
           SET hora_salida = v_hora
         WHERE id_usuario  = v_id_usuario
           AND fecha       = v_fecha
           AND resultado   = 'PERMITIDO'
           AND hora_salida IS NULL
           AND id_control <> p_id_control;
    END IF;

    SELECT p_id_control AS id_control, v_id_usuario AS id_usuario, p_resultado AS resultado,
           p_motivo AS motivo_rechazo, v_fecha AS fecha, v_hora AS hora_entrada;
END $$

-- =========================================
-- PROCEDIMIENTO 15: sp_registrar_salida
-- Marca la hora de salida en la última entrada abierta de hoy del
-- usuario identificado por su código RFID/QR.
-- Ejemplo: CALL sp_registrar_salida('QR-123456', @id_control);
-- =========================================
DROP PROCEDURE IF EXISTS sp_registrar_salida $$
CREATE PROCEDURE sp_registrar_salida(
    IN  p_codigo_acceso VARCHAR(60),
    OUT p_id_control    INT)
BEGIN
    DECLARE v_id_usuario INT;
    DECLARE v_hora       TIME DEFAULT TIME(DATE_FORMAT(NOW(), '%H:%i:00'));

    SELECT id_usuario INTO v_id_usuario FROM usuarios WHERE codigo_acceso = p_codigo_acceso;
    IF v_id_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Codigo de acceso invalido';
    END IF;

    SELECT id_control INTO p_id_control
      FROM control_acceso
     WHERE id_usuario  = v_id_usuario
       AND fecha       = CURDATE()
       AND resultado   = 'PERMITIDO'
       AND hora_salida IS NULL
     ORDER BY hora_entrada DESC, id_control DESC
     LIMIT 1;

    IF p_id_control IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El usuario no tiene una entrada abierta hoy';
    END IF;

    UPDATE control_acceso
       SET hora_salida = GREATEST(v_hora, hora_entrada)
     WHERE id_control = p_id_control;

    SELECT id_control, id_usuario, fecha, hora_entrada, hora_salida,
           TIMEDIFF(hora_salida, hora_entrada) AS permanencia
      FROM control_acceso WHERE id_control = p_id_control;
END $$

-- =========================================
-- PROCEDIMIENTO 16: sp_reporte_diario_asistencias
-- Resumen de un día (NULL = hoy): ingresos, usuarios únicos, rechazos,
-- entradas sin salida, permanencia promedio y hora pico; además el
-- detalle de ingresos por hora y por sede.
-- Ejemplo: CALL sp_reporte_diario_asistencias('2026-09-30');
-- =========================================
DROP PROCEDURE IF EXISTS sp_reporte_diario_asistencias $$
CREATE PROCEDURE sp_reporte_diario_asistencias(IN p_fecha DATE)
BEGIN
    DECLARE v_fecha DATE DEFAULT COALESCE(p_fecha, CURDATE());

    -- 1. Resumen del día
    SELECT v_fecha                                                   AS fecha,
           SUM(resultado = 'PERMITIDO')                              AS ingresos,
           COUNT(DISTINCT IF(resultado = 'PERMITIDO', id_usuario, NULL)) AS usuarios_unicos,
           SUM(resultado = 'DENEGADO')                               AS intentos_rechazados,
           SUM(resultado = 'PERMITIDO' AND hora_salida IS NULL)      AS sin_salida_registrada,
           SEC_TO_TIME(ROUND(AVG(IF(hora_salida IS NOT NULL,
                       TIME_TO_SEC(TIMEDIFF(hora_salida, hora_entrada)), NULL)))) AS permanencia_promedio,
           (SELECT CONCAT(LPAD(t.h, 2, '0'), ':00 - ', LPAD(t.h + 1, 2, '0'), ':00')
              FROM (SELECT HOUR(c2.hora_entrada) AS h, COUNT(*) AS n
                      FROM control_acceso c2
                     WHERE c2.fecha = v_fecha AND c2.resultado = 'PERMITIDO'
                     GROUP BY HOUR(c2.hora_entrada)) AS t
             ORDER BY t.n DESC, t.h
             LIMIT 1)                                                AS hora_pico
      FROM control_acceso
     WHERE fecha = v_fecha;

    -- 2. Ingresos por hora (para ver la curva del día)
    SELECT HOUR(hora_entrada) AS hora, COUNT(*) AS ingresos
      FROM control_acceso
     WHERE fecha = v_fecha AND resultado = 'PERMITIDO'
     GROUP BY HOUR(hora_entrada)
     ORDER BY hora;

    -- 3. Ingresos por sede
    SELECT s.nombre_sede,
           SUM(c.resultado = 'PERMITIDO') AS ingresos,
           SUM(c.resultado = 'DENEGADO')  AS rechazados
      FROM control_acceso c
      JOIN sedes_coworking s ON s.id_sede_coworking = c.id_sede_coworking
     WHERE c.fecha = v_fecha
     GROUP BY s.id_sede_coworking, s.nombre_sede
     ORDER BY ingresos DESC;
END $$

-- =========================================
-- PROCEDIMIENTO 17: sp_marcar_no_show
-- 1. Marca NO_SHOW las reservas CONFIRMADAS que ya terminaron sin
--    ninguna asistencia asociada.
-- 2. Recorre (cursor) las reservas NO_SHOW pagadas individualmente que
--    aún no tienen penalización y genera una venta con el cargo
--    (p_porcentaje % del valor de la reserva) y una notificación.
--    Las reservas corporativas se penalizan en la factura consolidada.
-- Ejemplo: CALL sp_marcar_no_show(20, @marcadas, @penalizadas);
-- =========================================
DROP PROCEDURE IF EXISTS sp_marcar_no_show $$
CREATE PROCEDURE sp_marcar_no_show(
    IN  p_porcentaje   DECIMAL(5,2),
    OUT p_marcadas     INT,
    OUT p_penalizadas  INT)
BEGIN
    DECLARE v_id_reserva INT;
    DECLARE v_id_usuario INT;
    DECLARE v_valor      DECIMAL(10,2);
    DECLARE v_cargo      DECIMAL(10,2);
    DECLARE v_id_venta   INT;
    DECLARE v_fin        BOOLEAN DEFAULT FALSE;
    DECLARE cur_no_show CURSOR FOR
        SELECT r.id_reserva, r.id_usuario, d.precio
          FROM reservas r
          JOIN detalles_venta d ON d.id_reserva = r.id_reserva AND d.concepto = 'RESERVA'
         WHERE r.estado = 'NO_SHOW'
           AND NOT EXISTS (SELECT 1 FROM detalles_venta p
                            WHERE p.id_reserva = r.id_reserva AND p.concepto = 'PENALIZACION');
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = TRUE;

    IF p_porcentaje IS NULL OR p_porcentaje <= 0 OR p_porcentaje > 100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje de penalizacion debe estar entre 0 y 100';
    END IF;

    UPDATE reservas r
       SET r.estado = 'NO_SHOW'
     WHERE r.estado = 'CONFIRMADA'
       AND r.fecha_fin < NOW()
       AND NOT EXISTS (SELECT 1 FROM registro_asistencias a WHERE a.id_reserva = r.id_reserva);
    SET p_marcadas = ROW_COUNT();

    SET p_penalizadas = 0;
    OPEN cur_no_show;
    recorrer: LOOP
        FETCH cur_no_show INTO v_id_reserva, v_id_usuario, v_valor;
        IF v_fin THEN LEAVE recorrer; END IF;

        SET v_cargo = ROUND(v_valor * p_porcentaje / 100, 2);
        INSERT INTO ventas (id_usuario, total) VALUES (v_id_usuario, v_cargo);
        SET v_id_venta = LAST_INSERT_ID();
        INSERT INTO detalles_venta (id_venta, id_reserva, concepto, precio)
        VALUES (v_id_venta, v_id_reserva, 'PENALIZACION', v_cargo);
        INSERT INTO notificaciones (id_usuario, destinatario, tipo, mensaje)
        VALUES (v_id_usuario, 'USUARIO', 'PENALIZACION_NO_SHOW',
                CONCAT('No asististe a la reserva #', v_id_reserva,
                       '. Se genero una penalizacion de $', v_cargo, ' + IVA.'));
        SET p_penalizadas = p_penalizadas + 1;
    END LOOP;
    CLOSE cur_no_show;

    SELECT p_marcadas AS reservas_marcadas_no_show, p_penalizadas AS penalizaciones_generadas;
END $$

-- =====================================================================
--  MÓDULO CORPORATIVOS Y ADMINISTRACIÓN (3)
-- =====================================================================

-- =========================================
-- PROCEDIMIENTO 18: sp_registrar_lote_empleados
-- Registra varios empleados de una empresa a partir de un arreglo JSON y
-- les asigna membresía CORPORATIVA (estado PENDIENTE hasta que la
-- empresa pague la factura consolidada).
--   * Si la persona ya existe (mismo documento) se reutiliza; si ya es
--     usuario, también.
--   * Campos por empleado: tipo_documento, numero_documento,
--     primer_nombre, segundo_nombre, primer_apellido, segundo_apellido,
--     fecha_nacimiento, telefono, email, nombre_usuario, contrasena
--     (hash bcrypt generado por la aplicación) y codigo_acceso.
--     nombre_usuario y codigo_acceso se generan si no vienen.
--   * Ante cualquier error hace ROLLBACK (si se llamó dentro de una
--     transacción) y relanza el error.
-- Ejemplo: ver 02_pruebas_procedimientos.sql
-- =========================================
DROP PROCEDURE IF EXISTS sp_registrar_lote_empleados $$
CREATE PROCEDURE sp_registrar_lote_empleados(
    IN  p_id_empresa    INT,
    IN  p_empleados     JSON,
    IN  p_fecha_inicio  DATE,
    OUT p_registrados   INT)
BEGIN
    DECLARE v_i          INT DEFAULT 0;
    DECLARE v_n          INT;
    DECLARE v_emp        JSON;
    DECLARE v_tipo_doc   VARCHAR(10);
    DECLARE v_doc        VARCHAR(20);
    DECLARE v_email      VARCHAR(150);
    DECLARE v_usuario    VARCHAR(30);
    DECLARE v_codigo     VARCHAR(60);
    DECLARE v_id_persona INT;
    DECLARE v_id_usuario INT;
    DECLARE v_id_corp    INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM empresas WHERE id_empresa = p_id_empresa) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no existe';
    END IF;
    IF p_empleados IS NULL OR JSON_TYPE(p_empleados) <> 'ARRAY' OR JSON_LENGTH(p_empleados) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_empleados debe ser un arreglo JSON con al menos un empleado';
    END IF;

    SELECT id_membresia INTO v_id_corp FROM membresias WHERE tipo_membresia = 'CORPORATIVA';
    SET v_n = JSON_LENGTH(p_empleados);
    SET p_registrados = 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_lote;
    CREATE TEMPORARY TABLE tmp_lote (id_usuario INT PRIMARY KEY);

    WHILE v_i < v_n DO
        SET v_emp      = JSON_EXTRACT(p_empleados, CONCAT('$[', v_i, ']'));
        SET v_tipo_doc = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.tipo_documento')), 'CC');
        SET v_doc      = JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.numero_documento'));
        SET v_email    = JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.email'));

        IF v_doc IS NULL OR v_email IS NULL
           OR JSON_EXTRACT(v_emp, '$.primer_nombre') IS NULL
           OR JSON_EXTRACT(v_emp, '$.primer_apellido') IS NULL
           OR JSON_EXTRACT(v_emp, '$.fecha_nacimiento') IS NULL
           OR JSON_EXTRACT(v_emp, '$.contrasena') IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Cada empleado requiere numero_documento, primer_nombre, primer_apellido, fecha_nacimiento, email y contrasena';
        END IF;

        -- Persona (se reutiliza si ya existe)
        SET v_id_persona = NULL;
        SELECT id_persona INTO v_id_persona FROM personas
         WHERE tipo_documento = v_tipo_doc AND numero_documento = v_doc;

        IF v_id_persona IS NULL THEN
            INSERT INTO personas (tipo_documento, numero_documento, primer_nombre, segundo_nombre,
                                  primer_apellido, segundo_apellido, fecha_nacimiento, telefono, email)
            VALUES (v_tipo_doc, v_doc,
                    JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.primer_nombre')),
                    JSON_UNQUOTE(NULLIF(JSON_EXTRACT(v_emp, '$.segundo_nombre'), CAST('null' AS JSON))),
                    JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.primer_apellido')),
                    JSON_UNQUOTE(NULLIF(JSON_EXTRACT(v_emp, '$.segundo_apellido'), CAST('null' AS JSON))),
                    JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.fecha_nacimiento')),
                    JSON_UNQUOTE(NULLIF(JSON_EXTRACT(v_emp, '$.telefono'), CAST('null' AS JSON))),
                    v_email);
            SET v_id_persona = LAST_INSERT_ID();
        END IF;

        -- Vínculo con la empresa
        INSERT IGNORE INTO empleados_empresa (id_persona, id_empresa, es_gerente)
        VALUES (v_id_persona, p_id_empresa, FALSE);

        -- Usuario (se reutiliza si ya existe)
        SET v_id_usuario = NULL;
        SELECT id_usuario INTO v_id_usuario FROM usuarios WHERE id_persona = v_id_persona;

        IF v_id_usuario IS NULL THEN
            SET v_usuario = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.nombre_usuario')),
                                     LOWER(CONCAT(LEFT(JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.primer_nombre')), 1),
                                                  JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.primer_apellido')),
                                                  v_id_persona)));
            SET v_codigo  = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.codigo_acceso')),
                                     CONCAT('QR-E', p_id_empresa, '-', v_id_persona));
            INSERT INTO usuarios (id_persona, nombre_usuario, contrasena, codigo_acceso)
            VALUES (v_id_persona, LEFT(v_usuario, 30),
                    JSON_UNQUOTE(JSON_EXTRACT(v_emp, '$.contrasena')), v_codigo);
            SET v_id_usuario = LAST_INSERT_ID();
        END IF;

        -- Membresía corporativa (fecha_fin la calcula el trigger)
        INSERT INTO suscripciones (id_usuario, id_membresia, fecha_inicio, fecha_fin, estado)
        VALUES (v_id_usuario, v_id_corp, COALESCE(p_fecha_inicio, CURDATE()),
                DATE_ADD(COALESCE(p_fecha_inicio, CURDATE()), INTERVAL 1 DAY), 'PENDIENTE');

        INSERT IGNORE INTO tmp_lote VALUES (v_id_usuario);
        SET p_registrados = p_registrados + 1;
        SET v_i = v_i + 1;
    END WHILE;

    SELECT u.id_usuario, u.nombre_usuario, u.codigo_acceso,
           CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
           e.razon_social AS empresa, s.fecha_inicio, s.fecha_fin, s.estado
      FROM tmp_lote t
      JOIN usuarios u           ON u.id_usuario = t.id_usuario
      JOIN personas p           ON p.id_persona = u.id_persona
      JOIN empresas e           ON e.id_empresa = p_id_empresa
      JOIN suscripciones s      ON s.id_usuario = u.id_usuario
                               AND s.id_suscripcion = (SELECT MAX(id_suscripcion) FROM suscripciones
                                                        WHERE id_usuario = u.id_usuario);
    DROP TEMPORARY TABLE IF EXISTS tmp_lote;
END $$

-- =========================================
-- PROCEDIMIENTO 19: sp_cancelar_reservas_futuras
-- Se usa al eliminar la membresía de un usuario: recorre (cursor) sus
-- reservas futuras PENDIENTES o CONFIRMADAS y las cancela una por una
-- con sp_cancelar_reserva (aplica la política de reembolso).
-- Ejemplo: CALL sp_cancelar_reservas_futuras(39, @n);
-- =========================================
DROP PROCEDURE IF EXISTS sp_cancelar_reservas_futuras $$
CREATE PROCEDURE sp_cancelar_reservas_futuras(
    IN  p_id_usuario INT,
    OUT p_canceladas INT)
BEGIN
    DECLARE v_id    INT;
    DECLARE v_monto DECIMAL(10,2);
    DECLARE v_total DECIMAL(10,2) DEFAULT 0;
    DECLARE v_fin   BOOLEAN DEFAULT FALSE;
    DECLARE cur_futuras CURSOR FOR
        SELECT id_reserva FROM reservas
         WHERE id_usuario = p_id_usuario
           AND estado IN ('PENDIENTE', 'CONFIRMADA')
           AND fecha_inicio > NOW()
         ORDER BY fecha_inicio;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = TRUE;

    IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    SET p_canceladas = 0;
    OPEN cur_futuras;
    recorrer: LOOP
        FETCH cur_futuras INTO v_id;
        IF v_fin THEN LEAVE recorrer; END IF;
        CALL sp_cancelar_reserva(v_id, NULL, v_monto);
        SET v_total = v_total + COALESCE(v_monto, 0);
        SET p_canceladas = p_canceladas + 1;
    END LOOP;
    CLOSE cur_futuras;

    SELECT p_id_usuario AS id_usuario, p_canceladas AS reservas_canceladas,
           v_total AS total_reembolsado;
END $$

-- =========================================
-- PROCEDIMIENTO 20: sp_reporte_ingresos_mensuales
-- Ingresos de cada mes del año (NULL = año actual) y acumulado del año:
--   * ingresos       = subtotal SIN IVA de facturas no anuladas emitidas.
--   * iva, facturado = IVA y total facturado (con IVA y recargos).
--   * recaudado      = pagos PAGADO recibidos en el mes.
-- Usa un CTE recursivo para listar los 12 meses aunque no tengan ventas
-- y funciones de ventana (OVER) para los acumulados.
-- Ejemplo: CALL sp_reporte_ingresos_mensuales(2026);
-- =========================================
DROP PROCEDURE IF EXISTS sp_reporte_ingresos_mensuales $$
CREATE PROCEDURE sp_reporte_ingresos_mensuales(IN p_anio INT)
BEGIN
    DECLARE v_anio INT DEFAULT COALESCE(p_anio, YEAR(CURDATE()));

    WITH RECURSIVE meses AS (
        SELECT 1 AS mes
        UNION ALL
        SELECT mes + 1 FROM meses WHERE mes < 12
    ),
    facturado AS (
        SELECT MONTH(fecha_emision) AS mes,
               SUM(subtotal) AS ingresos, SUM(iva) AS iva, SUM(total) AS facturado,
               COUNT(*) AS facturas
          FROM facturas
         WHERE estado <> 'ANULADA' AND YEAR(fecha_emision) = v_anio
         GROUP BY MONTH(fecha_emision)
    ),
    recaudado AS (
        SELECT MONTH(fecha_pago) AS mes, SUM(monto) AS recaudado
          FROM pagos
         WHERE estado = 'PAGADO' AND YEAR(fecha_pago) = v_anio
         GROUP BY MONTH(fecha_pago)
    )
    SELECT CONCAT(v_anio, '-', LPAD(m.mes, 2, '0'))               AS periodo,
           COALESCE(f.facturas, 0)                                 AS facturas,
           COALESCE(f.ingresos, 0)                                 AS ingresos_sin_iva,
           COALESCE(f.iva, 0)                                      AS iva,
           COALESCE(f.facturado, 0)                                AS total_facturado,
           COALESCE(r.recaudado, 0)                                AS recaudado,
           SUM(COALESCE(f.ingresos, 0))  OVER (ORDER BY m.mes)     AS ingresos_acumulados,
           SUM(COALESCE(r.recaudado, 0)) OVER (ORDER BY m.mes)     AS recaudado_acumulado
      FROM meses m
      LEFT JOIN facturado f ON f.mes = m.mes
      LEFT JOIN recaudado r ON r.mes = m.mes
     ORDER BY m.mes;
END $$

DELIMITER ;
