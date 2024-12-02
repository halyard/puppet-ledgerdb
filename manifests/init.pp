# @summary Configure Ledger DB instance
#
# @param datadir sets where the data is persisted
# @param hostname sets the hostname for influxdb
# @param aws_access_key_id sets the AWS key to use for Route53 challenge
# @param aws_secret_access_key sets the AWS secret key to use for the Route53 challenge
# @param email sets the contact address for the certificate
# @param ledger_repo is the git repo for ledger data
# @param ledger_ssh_key is the ssh key to use to update the repo
# @param ledger_file is the main ledger file to load, relative to the repo root
# @param version sets the ledgerdb tag to use
# @param user sets the user to run ledgerdb as
# @param bootdelay sets how long to wait before first run
# @param frequency sets how often to run updates
class ledgerdb (
  String $datadir,
  String $hostname,
  String $aws_access_key_id,
  String $aws_secret_access_key,
  String $email,
  String $ledger_repo,
  String $ledger_ssh_key,
  String $ledger_file = 'core.ldg',
  String $version = 'v0.0.10',
  String $user = 'ledgerdb',
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
      "${datadir}/influxdb",
    ]:
      ensure => directory,
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

  $binfile = '/usr/local/bin/ledgerdb'
  $filename = "ledgerdb_${downcase($facts['kernel'])}_${arch}"
  $url = "https://github.com/akerl/ledgerdb/releases/download/${version}/${filename}"

  exec { 'download ledgerdb':
    command => "/usr/bin/curl -sLo '${binfile}' '${url}' && chmod a+x '${binfile}'",
    unless  => "/usr/bin/test -f ${binfile} && ${binfile} version | grep '${version}'",
  }

  file { '/etc/systemd/system/ledgerdb.service':
    ensure  => file,
    content => template('ledgerdb/ledgerdb.service.erb'),
  }

  file { '/etc/systemd/system/ledgerdb.timer':
    ensure  => file,
    content => template('ledgerdb/ledgerdb.timer.erb'),
  }

  ~> service { 'ledgerdb.timer':
    ensure => running,
    enable => true,
  }

  class { 'influxdb':
    hostname              => $hostname,
    datadir               => "${datadir}/influxdb",
    aws_access_key_id     => $aws_access_key_id,
    aws_secret_access_key => $aws_secret_access_key,
    email                 => $email,
  }
}
