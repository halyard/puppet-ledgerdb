# @summary Configure Ledgergraph instance
#
# @param datadir sets where the data is persisted
# @param ledger_repo is the git repo for ledger data
# @param ledger_ssh_key is the ssh key to use to update the repo
# @param ledger_file is the main ledger file to load, relative to the repo root
# @param version sets the ledgergraph tag to use
# @param user sets the user to run ledgergraph as
# @param bootdelay sets how long to wait before first run
# @param frequency sets how often to run updates
class ledgergraph (
  String $datadir,
  String $ledger_repo,
  String $ledger_ssh_key,
  String $ledger_file = 'core.ldg',
  String $version = 'v0.1.0',
  String $user = 'ledgergraph',
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
    content => template('ledgergraph/config.yaml.erb'),
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

  $binfile = '/usr/local/bin/ledgergraph'
  $filename = "ledgergraph_${downcase($facts['kernel'])}_${arch}"
  $url = "https://github.com/akerl/ledgergraph/releases/download/${version}/${filename}"

  exec { 'download ledgergraph':
    command => "/usr/bin/curl -sLo '${binfile}' '${url}' && chmod a+x '${binfile}'",
    unless  => "/usr/bin/test -f ${binfile} && ${binfile} version | grep '${version}'",
  }

  file { '/etc/systemd/system/ledgergraph.service':
    ensure  => file,
    content => template('ledgergraph/ledgergraph.service.erb'),
  }

  ~> service { 'ledgergraph':
    ensure => running,
    enable => true,
  }
}
