# @summary Configure Ledger DB instance
#
# @param datadir sets where the data is persisted
# @param database_password sets the postgres password for grafana
# @param grafana_password is the password for Grafana to read from the DB
# @param ledger_repo is the git repo for ledger data
# @param ledger_ssh_key is the ssh key to use to update the repo
# @param ledger_file is the main ledger file to load, relative to the repo root
# @param version sets the ledgersql tag to use
# @param postgres_ip sets the address of the postgres Docker container
# @param user sets the user to run ledgersql as
# @param bootdelay sets how long to wait before first run
# @param frequency sets how often to run updates
class ledgerdb (
  String $datadir,
  String $database_password,
  String $grafana_password,
  String $ledger_repo,
  String $ledger_ssh_key,
  String $ledger_file = 'core.ldg',
  String $version = 'v0.0.8',
  String $postgres_ip = '172.17.0.3',
  String $user = 'ledgersql',
  String $bootdelay = '300',
  String $frequency = '300'
) {
  group { $user:
    ensure => present,
    system => true,
  }

  user { $user:
    ensure => present,
    system => true,
    gid    => $user,
    shell  => '/usr/bin/nologin',
    home   => $datadir,
  }

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
    todest => "${postgres_ip}:5432",
    table  => 'nat',
  }

  file { "${datadir}/init/setup.sh":
    ensure  => file,
    content => template('ledgerdb/setup.sh.erb'),
  }

  -> docker::container { 'postgres':
    image   => 'postgres:17',
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

  package { 'ledger': }

  file { "${datadir}/config.yaml":
    ensure  => file,
    content => template('ledgerdb/config.yaml.erb'),
    group   => $user,
    mode    => '0640',
  }

  $arch = $facts['os']['architecture'] ? {
    'x86_64'  => 'amd64',
    'arm64'   => 'arm64',
    'aarch64' => 'arm64',
    'arm'     => 'arm',
    default   => 'error',
  }

  $binfile = '/usr/local/bin/ledgersql'
  $filename = "ledgersql_${downcase($facts['kernel'])}_${arch}"
  $url = "https://github.com/akerl/ledgersql/releases/download/${version}/${filename}"

  exec { 'download ledgersql':
    command => "/usr/bin/curl -sLo '${binfile}' '${url}' && chmod a+x '${binfile}'",
    unless  => "/usr/bin/test -f ${binfile} && ${binfile} version | grep '${version}'",
  }

  file { '/etc/systemd/system/ledgersql.service':
    ensure  => file,
    content => template('ledgerdb/ledgersql.service.erb'),
  }

  file { '/etc/systemd/system/ledgersql.timer':
    ensure  => file,
    content => template('ledgerdb/ledgersql.timer.erb'),
  }

  ~> service { 'ledgersql.timer':
    ensure => running,
    enable => true,
  }
}
