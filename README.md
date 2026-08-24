# Swarm cluster deployment

Repozytorium zawiera provisioning Ansible oraz cztery stacki Docker Swarm.
Cały stan zarządzany przez projekt znajduje się na hostach pod
`/srv/cluster`; pliki release'u są instalowane wyłącznie na managerze.

- [Instrukcja Ansible](ansible/README.md)
- [Źródła release'u](apps/README.md)

Budowanie artefaktu:

```bash
./gradlew clusterRelease
tar -tzf build/distributions/cluster-release.tar.gz
```

Automatyczny deployment wykonuje workflow
`.github/workflows/update_cluster.yml`. Instaluje niezmienny release pod
`/srv/cluster/releases/<git-sha>`, przełącza symlink `/srv/cluster/current` i
uzgadnia stacki bez wcześniejszego zatrzymywania całego klastra.
