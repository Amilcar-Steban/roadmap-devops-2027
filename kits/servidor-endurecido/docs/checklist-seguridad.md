# Checklist de seguridad

- [ ] Root no puede entrar por SSH y no se aceptan contraseñas
- [ ] Solo el grupo `ssh-users` puede entrar por SSH
- [ ] El firewall deniega la entrada salvo 22, 80 y 443
- [ ] La API escucha solo en 127.0.0.1 y Nginx es el único punto de entrada
- [ ] HTTP redirige a HTTPS y el certificado es válido y se renueva solo
- [ ] Nginx no anuncia su versión (`server_tokens off`) y envía cabeceras de seguridad
- [ ] Los servicios corren con usuarios sin privilegios y endurecimiento de systemd
- [ ] Actualizaciones de seguridad automáticas activadas
- [ ] Backups diarios con rotación, y una restauración probada
- [ ] Todo el servidor se reproduce desde Git con `bootstrap.sh`
