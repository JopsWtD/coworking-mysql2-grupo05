/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Seguridad - roles
Archivo: 01_roles.sql
Descripción:
  Crea los 5 roles del sistema. Los permisos de cada rol se asignan en
  02_permisos.sql y los usuarios de ejemplo en 03_usuarios_ejemplo.sql.
Requisitos:
  Usuario con privilegio CREATE ROLE (por ejemplo root).
*/
USE coworking_grupo5;

-- Administrador del Coworking -> acceso total
CREATE ROLE IF NOT EXISTS 'rol_administrador';

-- Recepcionista -> registro de usuarios, asignación de membresías, gestión de reservas
CREATE ROLE IF NOT EXISTS 'rol_recepcionista';

-- Usuario -> reservar espacios, consultar su historial, descargar sus facturas
CREATE ROLE IF NOT EXISTS 'rol_usuario';

-- Gerente Corporativo -> administrar empleados de su empresa, ver facturación consolidada
CREATE ROLE IF NOT EXISTS 'rol_gerente_corporativo';

-- Contador -> gestión de ingresos y reportes financieros
CREATE ROLE IF NOT EXISTS 'rol_contador';

-- Verificación
SELECT user AS rol FROM mysql.user WHERE user LIKE 'rol\_%' ORDER BY user;
