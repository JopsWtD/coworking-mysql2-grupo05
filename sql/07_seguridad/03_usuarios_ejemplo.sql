/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Seguridad - usuarios de ejemplo
Archivo: 03_usuarios_ejemplo.sql
Descripción:
  Crea una cuenta MySQL por rol y le asigna su rol como predeterminado.
  Las cuentas de los roles Usuario y Gerente Corporativo se llaman igual
  que su nombre_usuario en la tabla usuarios (así las vistas v_mi_... y
  v_..._mi_empresa saben qué filas mostrar):
    * nflorez56 -> usuario independiente (id_usuario 56)
    * vpabon1   -> gerente de Innovatek S.A.S. (id_usuario 1)
  Las contraseñas son de ejemplo: cámbielas en un entorno real.
Requisitos:
  Ejecutar después de 01_roles.sql y 02_permisos.sql.
*/

-- Administrador del coworking
CREATE USER IF NOT EXISTS 'admin_coworking'@'localhost' IDENTIFIED BY 'Admin#Cowork2026';
GRANT 'rol_administrador' TO 'admin_coworking'@'localhost';
SET DEFAULT ROLE 'rol_administrador' TO 'admin_coworking'@'localhost';

-- Recepcionista
CREATE USER IF NOT EXISTS 'recepcion_centro'@'localhost' IDENTIFIED BY 'Recepcion#2026';
GRANT 'rol_recepcionista' TO 'recepcion_centro'@'localhost';
SET DEFAULT ROLE 'rol_recepcionista' TO 'recepcion_centro'@'localhost';

-- Usuario del coworking (cuenta = usuarios.nombre_usuario)
CREATE USER IF NOT EXISTS 'nflorez56'@'localhost' IDENTIFIED BY 'Usuario#2026';
GRANT 'rol_usuario' TO 'nflorez56'@'localhost';
SET DEFAULT ROLE 'rol_usuario' TO 'nflorez56'@'localhost';

-- Gerente corporativo de Innovatek (cuenta = usuarios.nombre_usuario)
CREATE USER IF NOT EXISTS 'vpabon1'@'localhost' IDENTIFIED BY 'Gerente#2026';
GRANT 'rol_gerente_corporativo' TO 'vpabon1'@'localhost';
SET DEFAULT ROLE 'rol_gerente_corporativo' TO 'vpabon1'@'localhost';

-- Contador
CREATE USER IF NOT EXISTS 'contador_coworking'@'localhost' IDENTIFIED BY 'Contador#2026';
GRANT 'rol_contador' TO 'contador_coworking'@'localhost';
SET DEFAULT ROLE 'rol_contador' TO 'contador_coworking'@'localhost';

-- Verificación: cuentas y sus roles
SELECT FROM_USER AS rol, TO_USER AS cuenta
FROM mysql.role_edges
WHERE FROM_USER LIKE 'rol\_%'
ORDER BY rol;

-- Para crear otro usuario con un rol:
--   CREATE USER 'nombre'@'localhost' IDENTIFIED BY 'clave';
--   GRANT 'rol_recepcionista' TO 'nombre'@'localhost';
--   SET DEFAULT ROLE ALL TO 'nombre'@'localhost';
