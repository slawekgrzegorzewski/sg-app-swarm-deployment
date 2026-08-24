# Plan dalszego rozwoju

## Zrealizowana baza

- wspólne inventory `home` i `test` z grupami funkcjonalnymi;
- idempotentny bootstrap Debiana/Ubuntu i Docker Engine;
- inicjalizacja oraz reset Docker Swarm;
- sieci overlay `cluster_network` i `application_network`;
- katalog główny `/srv/cluster` tworzony z grup inventory;
- etykiety `workload.*` uzgadniane z inventory wraz z usuwaniem starych
  etykiet;
- firewall UFW;
- sekrety pobierane przez lokalne 1Password CLI;
- automatyczne odnawianie certyfikatu i rotacja wersjonowanych Swarm secrets;
- niezmienne release'y instalowane wyłącznie na managerze.

## Następne usprawnienia

1. Dodać świadomą migrację danych dla zmiany `postgres_nodes` i
   `registry_nodes`, jeżeli klaster przestanie być środowiskiem odtwarzalnym.
2. Dodać automatyczny test integracyjny Vagrant: dwa wykonania `apply`,
   `check`, wdrożenie testowych stacków i kontrola `docker node ls`.
3. Uruchamiać w CI `ansible-lint`, `yamllint`, `shellcheck` oraz walidację
   wszystkich plików przez `docker stack config`.
4. Jeśli harmonogram wybudzania i wyłączania hostów pozostaje potrzebny,
   przenieść go ze starych skryptów operacyjnych do osobnej roli Ansible z
   wartościami MAC, interfejsu i kalendarza zapisanymi w inventory.
