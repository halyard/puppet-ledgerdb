# @summary Configure Ledger DB instance
#
# @param datadir sets where the data is persisted
# @param database_password sets the postgres password for grafana
# @param grafana_password is the password for Grafana to read from the DB
# @param ledger_repo is the git repo for ledger data
# @param ledger_ssh_key is the SSH key to use to update the repo
# @param postgres_ip sets the address of the postgres Docker container
class grafana (
  String $datadir,
  String $database_password,
  String $grafana_password,
  String $ledger_repo,
  String $ledger_ssh_key,
  String $postgres_ip = '172.17.0.3',
) {
  file { [
      $datadir,
      "${datadir}/data",
      "${datadir}/postgres",
      "${datadir}/init",
    ]:
      ensure => directory,
  }

  firewall { '100 dnat for postgres':
    chain  => 'DOCKER_EXPOSE',
    jump   => 'DNAT',
    proto  => 'tcp',
    dport  => 5432,
    todest => "${container_ip}:5432",
    table  => 'nat',
  }

  file { "${datadir}/init/setup.sh":
    ensure  => file,
    content => template('ledgerdb/setup.sh.erb'),
  }

  -> docker::container { 'postgres':
    image   => 'postgres:14',
    args    => [
      "--ip ${postgres_ip}",
      "-v ${datadir}/postgres:/var/lib/postgresql/data",
      "-v ${datadir}/init:/docker-entrypoint-initdb.d/",
      '-e POSTGRES_USER=admin',
      "-e POSTGRES_PASSWORD=${database_password}",
      '-e POSTGRES_DB=ledgerdb',
    ],
    cmd     => '-c ssl=on -c ssl_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem -c ssl_key_file=/etc/ssl/private/ssl-cert-snakeoil.key',
    require => File["${datadir}/postgres"],
  }

  file { "${datadir}/identity":
    ensure  => file,
    mode    => '0600',
    content => $ledger_ssh_key,
  }

  -> vcsrepo { "${datadir}/data":
    ensure   => latest,
    provider => git,
    source   => $ledger_repo,
    identity => "${datadir}/identity",
    revision => 'main',
  }
}
