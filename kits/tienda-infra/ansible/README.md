# Ansible: el servidor de la Fase 0

```bash
pipx install --include-deps ansible     # o: pipx install ansible-core && ansible-galaxy collection install -r requirements.yml
cd ansible
ansible web -m ansible.builtin.ping
ansible-playbook sitio.yml --check --diff
ansible-playbook sitio.yml              # dos veces: la segunda debe terminar con changed=0
```

Para probarlo sin VM, en un contenedor con systemd:

```bash
docker run -d --name web-01 --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  geerlingguy/docker-ubuntu2404-ansible
docker cp . web-01:/ansible
docker exec -w /ansible web-01 ansible-galaxy collection install -r requirements.yml
docker exec -w /ansible web-01 ansible-playbook -i inventario-contenedor.yml sitio.yml
docker exec -w /ansible web-01 ansible-playbook -i inventario-contenedor.yml sitio.yml   # changed=0
docker exec web-01 curl -s localhost
docker rm -f web-01
```

`inventario-contenedor.yml` desactiva el firewall (`comun_firewall: false`): ufw necesita los módulos de iptables del kernel del host.
