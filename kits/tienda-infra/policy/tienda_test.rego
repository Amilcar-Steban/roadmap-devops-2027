package main

import rego.v1

recurso(tipo, despues) := {"resource_changes": [{
	"address": sprintf("%s.x", [tipo]),
	"type": tipo,
	"change": {"actions": ["create"], "after": despues},
}]}

etiquetas(entorno) := {"proyecto": "tienda", "entorno": entorno, "equipo": "plataforma"}

test_bucket_con_etiquetas_pasa if {
	count(deny) == 0 with input as recurso("aws_s3_bucket", {"tags_all": etiquetas("dev")})
}

test_bucket_sin_equipo_falla if {
	some msg in deny with input as recurso("aws_s3_bucket", {"tags_all": {"proyecto": "tienda", "entorno": "dev"}})
	contains(msg, "equipo")
}

test_bd_publica_falla if {
	some msg in deny with input as recurso("aws_db_instance", {
		"tags_all": etiquetas("dev"),
		"publicly_accessible": true,
		"multi_az": false,
		"deletion_protection": false,
	})
	contains(msg, "publicly_accessible")
}

test_bd_prod_sin_multi_az_falla if {
	some msg in deny with input as recurso("aws_db_instance", {
		"tags_all": etiquetas("prod"),
		"publicly_accessible": false,
		"multi_az": false,
		"deletion_protection": true,
	})
	contains(msg, "Multi-AZ")
}

test_bd_dev_sin_multi_az_pasa if {
	count(deny) == 0 with input as recurso("aws_db_instance", {
		"tags_all": etiquetas("dev"),
		"publicly_accessible": false,
		"multi_az": false,
		"deletion_protection": false,
	})
}

test_bloqueo_publico_desactivado_falla if {
	some msg in deny with input as recurso("aws_s3_bucket_public_access_block", {
		"block_public_acls": true,
		"block_public_policy": false,
		"ignore_public_acls": true,
		"restrict_public_buckets": true,
	})
	contains(msg, "block_public_policy")
}

test_destruccion_avisa if {
	some msg in warn with input as {"resource_changes": [{
		"address": "aws_db_instance.x",
		"type": "aws_db_instance",
		"change": {"actions": ["delete"], "after": null},
	}]}
	contains(msg, "se destruirá")
}
