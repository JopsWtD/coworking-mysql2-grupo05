/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Triggers
Archivo: 01_triggers.sql
Descripción:
  20 triggers lógicos (25 físicos: algunos se implementan para INSERT y
  para UPDATE) en 4 módulos: Membresías, Reservas, Pagos y Facturación,
  Accesos. El orden entre triggers del mismo evento se fija con FOLLOWS.
Requisitos:
  Ejecutar DESPUÉS de cargar los datos (01_dml). Si los triggers existen
  al cargar el DML, el trigger 7 forzaría todas las reservas a PENDIENTE,
  el 6 rechazaría las dos reservas solapadas de prueba y los de accesos
  duplicarían asistencias y logs.
  Ejecutar con el cliente mysql o MySQL Workbench (usa DELIMITER).
*/
USE coworking_grupo5;

-- =====================================================================
--  MÓDULO MEMBRESIAS
--
--   1. Fecha de vencimiento automatica al crear una membresia
--   2. Membresia ACTIVA al realizarse un pago exitoso      (INSERT y UPDATE)
--   3. Membresia SUSPENDIDA si la factura vence sin pagarse
--   4. Log cada vez que cambia el tipo de membresia de un usuario
--   5. Bloquear eliminacion si el usuario tiene reservas activas confirmadas
-- =====================================================================
DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. Calcula fecha_fin segun el tipo (fecha_fin exclusiva):
--    DIARIA +1 dia | MENSUAL y CORPORATIVA +1 mes | PREMIUM +1 anio.
--    Si no se envia fecha_inicio, se usa hoy.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_suscripciones_bi_fecha_vencimiento$$
CREATE TRIGGER trg_suscripciones_bi_fecha_vencimiento
BEFORE INSERT ON suscripciones
FOR EACH ROW
BEGIN
    DECLARE v_tipo VARCHAR(20);
    SET NEW.fecha_inicio = COALESCE(NEW.fecha_inicio, CURDATE());
    SET v_tipo = (SELECT tipo_membresia FROM membresias WHERE id_membresia = NEW.id_membresia);
    SET NEW.fecha_fin = CASE v_tipo
        WHEN 'DIARIA'      THEN DATE_ADD(NEW.fecha_inicio, INTERVAL 1 DAY)
        WHEN 'MENSUAL'     THEN DATE_ADD(NEW.fecha_inicio, INTERVAL 1 MONTH)
        WHEN 'CORPORATIVA' THEN DATE_ADD(NEW.fecha_inicio, INTERVAL 1 MONTH)
        WHEN 'PREMIUM'     THEN DATE_ADD(NEW.fecha_inicio, INTERVAL 1 YEAR)
    END;
END$$

-- ---------------------------------------------------------------------
-- 2a. Pago PAGADO -> las membresias vendidas en esa venta pasan a ACTIVA
--     (o VENCIDA si se paga despues de su fecha de fin).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_ai_activar_membresia$$
CREATE TRIGGER trg_pagos_ai_activar_membresia
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado = 'PAGADO' THEN
        UPDATE suscripciones s
        JOIN detalles_venta d ON d.id_suscripcion = s.id_suscripcion
           SET s.estado = IF(s.fecha_fin > CURDATE(), 'ACTIVA', 'VENCIDA')
         WHERE d.id_venta = NEW.id_venta
           AND s.estado IN ('PENDIENTE', 'SUSPENDIDA');
    END IF;
END$$

-- 2b. Pago que pasa a PAGADO.
DROP TRIGGER IF EXISTS trg_pagos_au_activar_membresia$$
CREATE TRIGGER trg_pagos_au_activar_membresia
AFTER UPDATE ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado = 'PAGADO' AND OLD.estado <> 'PAGADO' THEN
        UPDATE suscripciones s
        JOIN detalles_venta d ON d.id_suscripcion = s.id_suscripcion
           SET s.estado = IF(s.fecha_fin > CURDATE(), 'ACTIVA', 'VENCIDA')
         WHERE d.id_venta = NEW.id_venta
           AND s.estado IN ('PENDIENTE', 'SUSPENDIDA');
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 3. Cuando una factura PENDIENTE con saldo se actualiza y ya paso su
--    fecha de vencimiento (p. ej. al aplicarle el recargo diario), sus
--    membresias se SUSPENDEN.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_facturas_au_suspender_membresia$$
CREATE TRIGGER trg_facturas_au_suspender_membresia
AFTER UPDATE ON facturas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'PENDIENTE'
       AND NEW.saldo_pendiente > 0
       AND NEW.fecha_vencimiento < CURDATE() THEN
        UPDATE suscripciones s
        JOIN detalles_venta d ON d.id_suscripcion = s.id_suscripcion
           SET s.estado = 'SUSPENDIDA'
         WHERE d.id_venta = NEW.id_venta
           AND s.estado IN ('PENDIENTE', 'ACTIVA');
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 4. Log en log_auditoria: 'Usuario 55: MENSUAL -> PREMIUM'
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_suscripciones_au_log_cambio_tipo$$
CREATE TRIGGER trg_suscripciones_au_log_cambio_tipo
AFTER UPDATE ON suscripciones
FOR EACH ROW
BEGIN
    IF NEW.id_membresia <> OLD.id_membresia THEN
        INSERT INTO log_auditoria (tabla_afectada, id_registro, accion, detalle)
        VALUES ('suscripciones', NEW.id_suscripcion, 'CAMBIO_TIPO_MEMBRESIA',
                CONCAT('Usuario ', NEW.id_usuario, ': ',
                       (SELECT tipo_membresia FROM membresias WHERE id_membresia = OLD.id_membresia),
                       ' -> ',
                       (SELECT tipo_membresia FROM membresias WHERE id_membresia = NEW.id_membresia)));
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 5. No se puede eliminar una membresia vigente si el usuario tiene
--    reservas CONFIRMADAS que aun no terminan. Las PENDIENTES se
--    cancelan con el trigger 9 (modulo Reservas) tras el borrado.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_suscripciones_bd_bloquear_eliminacion$$
CREATE TRIGGER trg_suscripciones_bd_bloquear_eliminacion
BEFORE DELETE ON suscripciones
FOR EACH ROW
BEGIN
    IF OLD.estado IN ('PENDIENTE', 'ACTIVA')
       AND EXISTS (SELECT 1 FROM reservas
                    WHERE id_usuario = OLD.id_usuario
                      AND estado = 'CONFIRMADA'
                      AND fecha_fin > NOW()) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar la membresia: el usuario tiene reservas activas confirmadas';
    END IF;
END$$
DELIMITER ;

-- =====================================================================
--  MÓDULO RESERVAS
--
--  6. Validar que no existan reservas duplicadas / solapadas
--  7. Estado inicial PENDIENTE (Pendiente de Confirmacion)
--  8. Estado CONFIRMADA al registrar el pago de la reserva (INSERT y UPDATE)
--  9. Cancelar reservas si el usuario elimina su membresia
-- 10. Log cada vez que una reserva es cancelada
-- =====================================================================

DELIMITER $$

-- ---------------------------------------------------------------------
-- 6. Rechaza una reserva que se cruce en horario con otra no cancelada
--    del mismo espacio (cubre el caso de mismo espacio, fecha y hora).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_reservas_bi_validar_duplicada$$
CREATE TRIGGER trg_reservas_bi_validar_duplicada
BEFORE INSERT ON reservas
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1
                 FROM reservas r
                WHERE r.id_espacio   = NEW.id_espacio
                  AND r.estado      <> 'CANCELADA'
                  AND r.fecha_inicio < NEW.fecha_fin
                  AND r.fecha_fin    > NEW.fecha_inicio) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El espacio ya esta reservado en ese horario';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 7. Toda reserva nueva nace en estado PENDIENTE, sin importar el valor enviado.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_reservas_bi_estado_pendiente$$
CREATE TRIGGER trg_reservas_bi_estado_pendiente
BEFORE INSERT ON reservas
FOR EACH ROW
FOLLOWS trg_reservas_bi_validar_duplicada
BEGIN
    SET NEW.estado = 'PENDIENTE';
END$$

-- ---------------------------------------------------------------------
-- 8a. Pago PAGADO insertado -> confirma las reservas de esa venta.
--     Solo concepto RESERVA (la PENALIZACION no confirma nada).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_ai_confirmar_reserva$$
CREATE TRIGGER trg_pagos_ai_confirmar_reserva
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado = 'PAGADO' THEN
        UPDATE reservas r
        JOIN detalles_venta d ON d.id_reserva = r.id_reserva
           SET r.estado = 'CONFIRMADA'
         WHERE d.id_venta = NEW.id_venta
           AND d.concepto = 'RESERVA'
           AND r.estado   = 'PENDIENTE';
    END IF;
END$$

-- 8b. Pago que pasa a PAGADO.
DROP TRIGGER IF EXISTS trg_pagos_au_confirmar_reserva$$
CREATE TRIGGER trg_pagos_au_confirmar_reserva
AFTER UPDATE ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado = 'PAGADO' AND OLD.estado <> 'PAGADO' THEN
        UPDATE reservas r
        JOIN detalles_venta d ON d.id_reserva = r.id_reserva
           SET r.estado = 'CONFIRMADA'
         WHERE d.id_venta = NEW.id_venta
           AND d.concepto = 'RESERVA'
           AND r.estado   = 'PENDIENTE';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 9. Al eliminar una membresia vigente, cancela las reservas futuras
--    PENDIENTE/CONFIRMADA del usuario, siempre que no le quede otra
--    membresia activa. (Las CONFIRMADAS vigentes ya impiden el borrado
--    por el trigger del modulo Membresias.)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_suscripciones_ad_cancelar_reservas$$
CREATE TRIGGER trg_suscripciones_ad_cancelar_reservas
AFTER DELETE ON suscripciones
FOR EACH ROW
BEGIN
    IF OLD.estado IN ('PENDIENTE', 'ACTIVA', 'SUSPENDIDA')
       AND NOT EXISTS (SELECT 1
                         FROM suscripciones
                        WHERE id_usuario = OLD.id_usuario
                          AND estado = 'ACTIVA'
                          AND fecha_fin >= CURDATE()) THEN
        UPDATE reservas
           SET estado = 'CANCELADA'
         WHERE id_usuario   = OLD.id_usuario
           AND estado       IN ('PENDIENTE', 'CONFIRMADA')
           AND fecha_inicio > NOW();
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 10. Registra en log_auditoria cada cancelacion de reserva.
--     Tambien deja log de las canceladas por el trigger anterior.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_reservas_au_log_cancelacion$$
CREATE TRIGGER trg_reservas_au_log_cancelacion
AFTER UPDATE ON reservas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'CANCELADA' AND OLD.estado <> 'CANCELADA' THEN
        INSERT INTO log_auditoria (tabla_afectada, id_registro, accion, detalle)
        VALUES ('reservas',
                NEW.id_reserva,
                'CANCELACION',
                CONCAT('Reserva cancelada por el usuario ', NEW.id_usuario));
    END IF;
END$$

DELIMITER ;

-- =====================================================================
--  MÓDULO PAGOS Y FACTURACION
--
--  11. Crear factura automaticamente al registrar un pago
--  12. Actualizar saldo pendiente (pagos parciales)       (INSERT y UPDATE)
--  13. Factura a PAGADA cuando se confirma el pago        (INSERT y UPDATE)
--  14. Bloquear eliminacion de un pago con factura asociada
--  15. Log de todos los pagos anulados                    (INSERT y UPDATE)
--
--  Orden de ejecucion en un pago nuevo:
--     crear factura -> actualizar saldo -> marcar PAGADA   (usa FOLLOWS)
--  IVA: 19 %.
-- =====================================================================

DELIMITER $$

-- ---------------------------------------------------------------------
-- 11. Si la venta aun no tiene factura (relacion 1:1), la crea
--     (salvo que el pago se registre ya CANCELADO).
--     Subtotal = ventas.total (sin IVA); vence a 15 dias.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_ai_crear_factura$$
CREATE TRIGGER trg_pagos_ai_crear_factura
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    DECLARE v_subtotal DECIMAL(10,2);
    DECLARE v_iva      DECIMAL(10,2);
    DECLARE v_num      INT;

    -- Un pago CANCELADO no genera factura
    IF NEW.estado <> 'CANCELADO'
       AND NOT EXISTS (SELECT 1 FROM facturas WHERE id_venta = NEW.id_venta) THEN
        SET v_subtotal = (SELECT total FROM ventas WHERE id_venta = NEW.id_venta);
        SET v_iva      = ROUND(v_subtotal * 0.19, 2);
        SET v_num      = (SELECT COALESCE(MAX(id_factura), 0) + 1 FROM facturas);

        INSERT INTO facturas (id_venta, numero_factura, fecha_emision, fecha_vencimiento,
                              subtotal, iva, recargo, total, saldo_pendiente, estado)
        VALUES (NEW.id_venta,
                CONCAT('FV-', LPAD(v_num, 6, '0')),
                CURDATE(),
                DATE_ADD(CURDATE(), INTERVAL 15 DAY),
                v_subtotal, v_iva, 0, v_subtotal + v_iva, v_subtotal + v_iva,
                'PENDIENTE');
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 12a. Recalcula saldo_pendiente = total - suma de pagos PAGADOS de la venta.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_ai_actualizar_saldo$$
CREATE TRIGGER trg_pagos_ai_actualizar_saldo
AFTER INSERT ON pagos
FOR EACH ROW
FOLLOWS trg_pagos_ai_crear_factura
BEGIN
    DECLARE v_pagado DECIMAL(10,2);

    IF NEW.estado = 'PAGADO' THEN
        SET v_pagado = (SELECT COALESCE(SUM(monto), 0)
                          FROM pagos
                         WHERE id_venta = NEW.id_venta
                           AND estado = 'PAGADO');

        UPDATE facturas
           SET saldo_pendiente = GREATEST(total - v_pagado, 0)
         WHERE id_venta = NEW.id_venta
           AND estado <> 'ANULADA';
    END IF;
END$$

-- 12b. Recalcula cuando cambia el estado o el monto de un pago.
--      Si un pago se anula y vuelve a quedar saldo, una factura PAGADA
--      regresa a PENDIENTE.
DROP TRIGGER IF EXISTS trg_pagos_au_actualizar_saldo$$
CREATE TRIGGER trg_pagos_au_actualizar_saldo
AFTER UPDATE ON pagos
FOR EACH ROW
BEGIN
    DECLARE v_pagado DECIMAL(10,2);

    IF NEW.estado <> OLD.estado OR NEW.monto <> OLD.monto THEN
        SET v_pagado = (SELECT COALESCE(SUM(monto), 0)
                          FROM pagos
                         WHERE id_venta = NEW.id_venta
                           AND estado = 'PAGADO');

        UPDATE facturas
           SET saldo_pendiente = GREATEST(total - v_pagado, 0),
               estado = CASE WHEN estado = 'PAGADA' AND total - v_pagado > 0
                             THEN 'PENDIENTE' ELSE estado END
         WHERE id_venta = NEW.id_venta
           AND estado <> 'ANULADA';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 13a. Con el pago confirmado y saldo en 0, la factura pasa a PAGADA.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_ai_factura_pagada$$
CREATE TRIGGER trg_pagos_ai_factura_pagada
AFTER INSERT ON pagos
FOR EACH ROW
FOLLOWS trg_pagos_ai_actualizar_saldo
BEGIN
    IF NEW.estado = 'PAGADO' THEN
        UPDATE facturas
           SET estado = 'PAGADA'
         WHERE id_venta = NEW.id_venta
           AND estado = 'PENDIENTE'
           AND saldo_pendiente = 0;
    END IF;
END$$

-- 13b. Pago que pasa a PAGADO.
DROP TRIGGER IF EXISTS trg_pagos_au_factura_pagada$$
CREATE TRIGGER trg_pagos_au_factura_pagada
AFTER UPDATE ON pagos
FOR EACH ROW
FOLLOWS trg_pagos_au_actualizar_saldo
BEGIN
    IF NEW.estado = 'PAGADO' AND OLD.estado <> 'PAGADO' THEN
        UPDATE facturas
           SET estado = 'PAGADA'
         WHERE id_venta = NEW.id_venta
           AND estado = 'PENDIENTE'
           AND saldo_pendiente = 0;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 14. No se puede borrar un pago si su venta ya tiene factura.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_bd_bloquear_eliminacion$$
CREATE TRIGGER trg_pagos_bd_bloquear_eliminacion
BEFORE DELETE ON pagos
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM facturas WHERE id_venta = OLD.id_venta) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar el pago: ya existe una factura asociada';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 15a. Log cuando un pago pasa a CANCELADO.
--      Formato igual al de los datos: 'Pago de $128.52 anulado'
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_au_log_anulacion$$
CREATE TRIGGER trg_pagos_au_log_anulacion
AFTER UPDATE ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado = 'CANCELADO' AND OLD.estado <> 'CANCELADO' THEN
        INSERT INTO log_auditoria (tabla_afectada, id_registro, accion, detalle)
        VALUES ('pagos', NEW.id_pago, 'ANULACION_PAGO',
                CONCAT('Pago de $', NEW.monto, ' anulado'));
    END IF;
END$$

-- 15b. Log si el pago se registra directamente como CANCELADO.
DROP TRIGGER IF EXISTS trg_pagos_ai_log_anulacion$$
CREATE TRIGGER trg_pagos_ai_log_anulacion
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado = 'CANCELADO' THEN
        INSERT INTO log_auditoria (tabla_afectada, id_registro, accion, detalle)
        VALUES ('pagos', NEW.id_pago, 'ANULACION_PAGO',
                CONCAT('Pago de $', NEW.monto, ' anulado'));
    END IF;
END$$

DELIMITER ;

-- =====================================================================
--  MÓDULO ACCESOS
--
--  16. Registrar asistencia automaticamente al validar acceso (QR / RFID)
--  17. Bloquear acceso si no hay membresia activa ni reserva (ni horario)
--  18. Actualizar ultimo acceso del usuario
--  19. Registrar salida automatica si vuelve a entrar sin salida previa
--  20. Log de cada intento de acceso rechazado
--
--  Orden BEFORE INSERT: validar acceso (17) -> salida automatica (19)
--  Orden AFTER  INSERT: asistencia (16) -> ultimo acceso (18) -> log (20)
-- =====================================================================

DELIMITER $$

-- ---------------------------------------------------------------------
-- 17. Valida el intento ANTES de guardarlo. No lanza error: si no cumple,
--     el registro queda como DENEGADO con su motivo, asi el intento se
--     conserva y el trigger de log (20) lo registra.
--     Reglas (en orden):
--       a) Sede cerrada o fuera de horarios_atencion -> FUERA_DE_HORARIO
--       b) Membresia ACTIVA vigente  -> permitido
--       c) Reserva CONFIRMADA ese dia en esa sede (aun sin terminar) ->
--          permitido y se asocia id_reserva
--       d) Ninguna -> MEMBRESIA_INACTIVA (si tiene suscripciones) o SIN_RESERVA
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_control_acceso_bi_validar_acceso$$
CREATE TRIGGER trg_control_acceso_bi_validar_acceso
BEFORE INSERT ON control_acceso
FOR EACH ROW
BEGIN
    DECLARE v_fecha     DATE;
    DECLARE v_dia       VARCHAR(10);
    DECLARE v_abre      TIME;
    DECLARE v_cierra    TIME;
    DECLARE v_membresia INT DEFAULT 0;
    DECLARE v_reserva   INT DEFAULT NULL;
    DECLARE v_suscrito  INT DEFAULT 0;

    IF NEW.id_usuario IS NOT NULL AND NEW.resultado = 'PERMITIDO' THEN

        SET v_fecha = COALESCE(NEW.fecha, CURDATE());
        SET v_dia   = ELT(WEEKDAY(v_fecha) + 1,
                          'LUNES','MARTES','MIERCOLES','JUEVES','VIERNES','SABADO','DOMINGO');

        SET v_abre   = (SELECT hora_inicio FROM horarios_atencion
                         WHERE id_sede_coworking = NEW.id_sede_coworking AND dia_semana = v_dia);
        SET v_cierra = (SELECT hora_fin FROM horarios_atencion
                         WHERE id_sede_coworking = NEW.id_sede_coworking AND dia_semana = v_dia);

        IF v_abre IS NULL OR NEW.hora_entrada < v_abre OR NEW.hora_entrada >= v_cierra THEN
            SET NEW.resultado      = 'DENEGADO';
            SET NEW.motivo_rechazo = 'FUERA_DE_HORARIO';
            SET NEW.hora_salida    = NULL;
        ELSE
            SET v_membresia = (SELECT COUNT(*) FROM suscripciones
                                WHERE id_usuario = NEW.id_usuario
                                  AND estado = 'ACTIVA'
                                  AND v_fecha >= fecha_inicio
                                  AND v_fecha <  fecha_fin);

            -- La reserva debe ser en un espacio de la sede donde se intenta entrar
            SET v_reserva = (SELECT r.id_reserva
                               FROM reservas r
                               JOIN espacios e ON e.id_espacio = r.id_espacio
                              WHERE r.id_usuario = NEW.id_usuario
                                AND r.estado = 'CONFIRMADA'
                                AND e.id_sede_coworking = NEW.id_sede_coworking
                                AND DATE(r.fecha_inicio) = v_fecha
                                AND NEW.hora_entrada < TIME(r.fecha_fin)
                              ORDER BY r.fecha_inicio
                              LIMIT 1);

            IF v_reserva IS NOT NULL THEN
                SET NEW.id_reserva = v_reserva;
            END IF;

            IF v_membresia = 0 AND v_reserva IS NULL THEN
                SET v_suscrito = (SELECT COUNT(*) FROM suscripciones
                                   WHERE id_usuario = NEW.id_usuario);
                SET NEW.resultado      = 'DENEGADO';
                SET NEW.motivo_rechazo = IF(v_suscrito > 0, 'MEMBRESIA_INACTIVA', 'SIN_RESERVA');
                SET NEW.hora_salida    = NULL;
            END IF;
        END IF;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 19. Si el usuario entra de nuevo sin haber registrado salida de su
--     entrada anterior del mismo dia, se deja constancia de la salida
--     automatica en log_auditoria (hora de salida = hora de la nueva entrada).
--
--     LIMITACION DE MYSQL: un trigger de control_acceso NO puede hacer
--     UPDATE sobre control_acceso (error 1442), por eso aqui no se puede
--     completar hora_salida de la fila anterior. Ese UPDATE debe hacerse en
--     el procedimiento sp_registrar_entrada (04_procedimientos), que
--     completa la salida anterior despues del INSERT.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_control_acceso_bi_salida_automatica$$
CREATE TRIGGER trg_control_acceso_bi_salida_automatica
BEFORE INSERT ON control_acceso
FOR EACH ROW
FOLLOWS trg_control_acceso_bi_validar_acceso
BEGIN
    DECLARE v_abierta INT;

    IF NEW.id_usuario IS NOT NULL AND NEW.resultado = 'PERMITIDO' THEN
        SET v_abierta = (SELECT id_control
                           FROM control_acceso
                          WHERE id_usuario  = NEW.id_usuario
                            AND resultado   = 'PERMITIDO'
                            AND hora_salida IS NULL
                            AND fecha       = COALESCE(NEW.fecha, CURDATE())
                          ORDER BY id_control DESC
                          LIMIT 1);

        IF v_abierta IS NOT NULL THEN
            INSERT INTO log_auditoria (tabla_afectada, id_registro, accion, detalle)
            VALUES ('control_acceso', v_abierta, 'SALIDA_AUTOMATICA',
                    CONCAT('Usuario ', NEW.id_usuario,
                           ' volvio a entrar sin salida previa; salida asignada a las ',
                           NEW.hora_entrada));
        END IF;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 16. Acceso PERMITIDO -> registra la asistencia.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_control_acceso_ai_registrar_asistencia$$
CREATE TRIGGER trg_control_acceso_ai_registrar_asistencia
AFTER INSERT ON control_acceso
FOR EACH ROW
BEGIN
    IF NEW.resultado = 'PERMITIDO' AND NEW.id_usuario IS NOT NULL THEN
        INSERT INTO registro_asistencias (id_usuario, id_sede_coworking, id_reserva, fecha_hora)
        VALUES (NEW.id_usuario, NEW.id_sede_coworking, NEW.id_reserva,
                TIMESTAMP(NEW.fecha, NEW.hora_entrada));
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 18. Acceso PERMITIDO -> actualiza usuarios.ultimo_acceso
--     (sin retroceder si se registra un acceso con fecha anterior).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_control_acceso_ai_ultimo_acceso$$
CREATE TRIGGER trg_control_acceso_ai_ultimo_acceso
AFTER INSERT ON control_acceso
FOR EACH ROW
FOLLOWS trg_control_acceso_ai_registrar_asistencia
BEGIN
    IF NEW.resultado = 'PERMITIDO' AND NEW.id_usuario IS NOT NULL THEN
        UPDATE usuarios
           SET ultimo_acceso = GREATEST(COALESCE(ultimo_acceso, TIMESTAMP(NEW.fecha, NEW.hora_entrada)),
                                        TIMESTAMP(NEW.fecha, NEW.hora_entrada))
         WHERE id_usuario = NEW.id_usuario;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 20. Acceso DENEGADO -> registra el intento en log_auditoria.
--     Formato igual al de los datos: 'Motivo: MEMBRESIA_INACTIVA'
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_control_acceso_ai_log_rechazo$$
CREATE TRIGGER trg_control_acceso_ai_log_rechazo
AFTER INSERT ON control_acceso
FOR EACH ROW
FOLLOWS trg_control_acceso_ai_ultimo_acceso
BEGIN
    IF NEW.resultado = 'DENEGADO' THEN
        INSERT INTO log_auditoria (tabla_afectada, id_registro, accion, detalle, fecha_hora)
        VALUES ('control_acceso', NEW.id_control, 'ACCESO_RECHAZADO',
                CONCAT('Motivo: ', NEW.motivo_rechazo),
                TIMESTAMP(NEW.fecha, NEW.hora_entrada));
    END IF;
END$$

DELIMITER ;
