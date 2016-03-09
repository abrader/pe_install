class pe_install (
  $is_spde_dev           = $::is_spde_dev,
  $pe_version            = $::pe_version,
  $cwd                   = $::cwd,
  $gms_token             = 'aSaduY8ywcshtnjDzHup',
  $gms_server_url        = 'http://140.188.246.24',
  $gms_project_name      = 'SLEP-II/control',
  $control_repo          = 'git@140.188.246.24:SLEP-II/control.git',
  $code_manager_key_path = '/etc/puppetlabs/puppetserver/ssh',
) {
  $code_manager_private_key_path = "${code_manager_key_path}/id-control_repo.rsa"
  $code_manager_public_key_path  = "${code_manager_key_path}/id-control_repo.pub"
  $target_dir                    = "/opt/staging/${module_name}"
  $pe_tarball_path               = "${target_dir}/puppet-enterprise-${pe_version}-el-7-x86_64"
  $pe_tarball                    = "${cwd}/puppet-enterprise-${pe_version}-el-7-x86_64.tar.gz"
  $staging_file                  = "puppet-enterprise-${pe_version}-el-7-x86_64.tar.gz"
  $answers_file                  = "${target_dir}/geodss_answers_file"

  host { "Add record for ${::fqdn}":
    name    => $::fqdn,
    ensure  => present,
    ip      => $::ipaddress_enp0s8,
    comment => 'SLEP-II Puppet Master - Dev',
  }

  # -- File resources below this code will be applied to all files as default

  File {
    owner => 'root',
    group => 'root',
    mode  => '0700',
  }

  file { $pe_tarball:
    ensure => file,
  }

  staging::file { $staging_file:
    source  => $pe_tarball,
    require => File[$pe_tarball],
  }

  staging::extract { $staging_file:
    target  => $target_dir,
    creates => '/opt/staging/puppet-enterprise-installer',
    require => Staging::File[$staging_file],
  }

  file { 'Create Answers File':
    ensure  => file,
    path    => $answers_file,
    content => template('pe_install/answers_file.erb'),
  }

  exec { 'Installing Puppet Enterprise':
    command => "${pe_tarball_path}/puppet-enterprise-installer -a ${answers_file}",
    onlyif  => '/bin/rpm -qa pe-puppet-server',
    timeout => 0,
    require => [ File['Create Answers File'], Staging::Extract[$staging_file] ],
    before  => Vcsrepo['/etc/puppetlabs/code/modules/pe_install'],
  }

  service { 'firewalld':
    ensure  => stopped,
    enable  => false,
    require => Exec['Installing Puppet Enterprise'],
  }

  file { 'Install custom hiera.yaml':
    ensure  => file,
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0644',
    path    => '/etc/puppetlabs/code/hiera.yaml',
    source  => 'puppet:///modules/pe_install/hiera.yaml',
    require => Service['firewalld'],
  }

  # Create directory for Puppet to store public key for Code Manager use
  $code_manager_pub_dirs = ['/etc/puppetlabs/puppetserver', '/etc/puppetlabs/puppetserver/ssh']

  file { $code_manager_pub_dirs:
    ensure  => directory,
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0750',
    require => Service['firewalld'],
  }

  file { 'Private key for Code Manager':
    ensure  => file,
    path    => $code_manager_private_key_path,
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0600',
    source  => 'puppet:///modules/pe_install/code_manager_private',
    require => Service['firewalld'],
    # before  => Git_Deploy_Key['Code Manager Deploy Key'],
  }

  file { 'Public key for Code Manager':
    ensure  => file,
    path    => $code_manager_public_key_path,
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0600',
    source  => 'puppet:///modules/pe_install/code_manager_public',
    require => Service['firewalld'],
    # before  => Git_Deploy_Key['Code Manager Deploy Key'],
  }

  file { 'Temporary path for local Puppetclassify gem file':
    ensure   => file,
    path     => "${target_dir}/puppetclassify-0.1.3.gem",
    source   => 'puppet:///modules/pe_install/puppetclassify-0.1.3.gem',
    require  => Service['firewalld'],
  }

  package { 'Install Puppetclassify Gem':
    ensure   => present,
    name     => 'puppetclassify',
    source   =>  "${target_dir}/puppetclassify-0.1.3.gem",
    provider => 'puppet_gem',
    require  => File['Temporary path for local Puppetclassify gem file'],
    before   => [ Node_Group['Production environment'], Node_Group['Agent-specified environment'] ],
  }

  package { 'git':
    ensure => present,
  }

  vcsrepo { '/etc/puppetlabs/code/modules/pe_install':
    ensure   => present,
    provider => git,
    #source   => 'git@dev-gitlab1:SLEP-II/pe_install.git',
    source   => 'https://github.com/abrader/pe_install.git',
    revision => 'development',
    owner    => 'pe-puppet',
    group    => 'pe-puppet',
    require  => Package['git'],
    before   => Service['firewalld'],
  }

#  node_group { 'PE Master':
#    ensure                             => present,
#    classes                            => {
#      'pe_repo'                            => {},
#      'pe_repo::platform::el_7_x86_64'     => {},
#      'pe_install::hocon'                  => {},
#      'puppet_enterprise::profile::master' =>
#      {
#        'code_manager_auto_configure' => true,
#        'file_sync_enabled'           => true,
#        'r10k_private_key'            => $code_manager_private_key_path,
#        'r10k_remote'                 => $control_repo
#      },
#      'puppet_enterprise::master::code_manager' =>
#      {
#        'authenticate_webhook' => false
#      },
#      'puppet_enterprise::profile::master::mcollective'  => {},
#      'puppet_enterprise::profile::mcollective::peadmin' => {}
#    },
#    environment => 'production',
#    parent      => 'PE Infrastructure',
#    require     => Vcsrepo['/etc/puppetlabs/code/modules/pe_install']
#  }

  node_group { 'Production environment':
    ensure               => present,
    environment          => 'production',
    override_environment => true,
    parent               => 'All Nodes',
    rule                 => ['and', ['~', 'name', '.*']],
  }

  node_group { 'Agent-specified environment':
    ensure               => present,
    environment          => 'agent-specified',
    override_environment => true,
    parent               => 'Production environment',
    rule                 => ['and', ['~', 'name', '.*']],
  }

  # git_deploy_key { 'Code Manager Deploy Key':
  #   ensure             => present,
  #   name               => $::fqdn,
  #   path               => $code_manager_public_key_path,
  #   token              => $gms_token,
  #   project_name       => $gms_project_name,
  #   server_url         => $gms_server_url,
  #   provider           => 'gitlab',
  #   require            => File['Public key for Code Manager'],
  #   before             => Node_Group['Agent-specified environment'],
  # }

#   git_webhook { 'Code_Manager_Webhook':
#     ensure             => present,
#     token              => $gms_token,
#     project_name       => $gms_project_name,
#     server_url         => $gms_server_url,
#     webhook_url        => "https://${::ipaddress}:8170/code-manager/v1/webhook?type=github",
#     provider           => 'gitlab',
#     require            => File['Public key for Code Manager'],
#     before             => Node_Group['Agent-specified environment'],
#     disable_ssl_verify => false,
# }

  service { 'pe-puppetserver':
    ensure    => running,
    enable    => true,
    require   => Service['firewalld'],
    subscribe => File['Install custom hiera.yaml'],
  }

}
