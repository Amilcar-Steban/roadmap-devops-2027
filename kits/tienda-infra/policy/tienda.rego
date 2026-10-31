# Reglas de la organización que se comprueban sobre el plan (terraform show -json tfplan).
#   conftest test plan.json -p policy        · probar las reglas: conftest verify -p policy
package main

import rego.v1

etiquetas_obligatorias := {"proyecto", "entorno", "equipo"}

creados_o_cambiados contains rc if {
	some rc in input.resource_changes
	some accion in rc.change.actions
	accion in {"create", "update"}
}

# 1. Todo recurso de AWS con etiquetas debe llevar las obligatorias (default_tags las pone)
deny contains msg if {
	some rc in creados_o_cambiados
	startswith(rc.type, "aws_")
	"tags_all" in object.keys(rc.change.after)
	faltan := etiquetas_obligatorias - {k | some k, _ in object.get(rc.change.after, "tags_all", {})}
	count(faltan) > 0
	msg := sprintf("%s: faltan las etiquetas %v", [rc.address, sort(faltan)])
}

# 2. Ninguna base de datos accesible desde internet
deny contains msg if {
	some rc in creados_o_cambiados
	rc.type == "aws_db_instance"
	rc.change.after.publicly_accessible == true
	msg := sprintf("%s: publicly_accessible debe ser false", [rc.address])
}

# 3. El bloqueo de acceso público de S3 no se desactiva
deny contains msg if {
	some rc in creados_o_cambiados
	rc.type == "aws_s3_bucket_public_access_block"
	some opcion in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]
	rc.change.after[opcion] == false
	msg := sprintf("%s: %s debe ser true", [rc.address, opcion])
}

# 4. En producción, la base de datos es Multi-AZ y está protegida contra borrado
deny contains msg if {
	some rc in creados_o_cambiados
	rc.type == "aws_db_instance"
	rc.change.after.tags_all.entorno == "prod"
	not rc.change.after.multi_az
	msg := sprintf("%s: en prod debe ser Multi-AZ", [rc.address])
}

deny contains msg if {
	some rc in creados_o_cambiados
	rc.type == "aws_db_instance"
	rc.change.after.tags_all.entorno == "prod"
	not rc.change.after.deletion_protection
	msg := sprintf("%s: en prod debe tener deletion_protection", [rc.address])
}

# 5. Avisar (sin bloquear) de cualquier destrucción, para que se mire con lupa en la revisión
warn contains msg if {
	some rc in input.resource_changes
	"delete" in rc.change.actions
	msg := sprintf("%s se destruirá (%v)", [rc.address, rc.change.actions])
}
