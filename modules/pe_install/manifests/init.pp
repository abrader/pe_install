class pe_install (
  $is_spde_dev               = $::is_spde_dev,
  $pe_version                = $::pe_version,
  $cwd                       = $::cwd,
  $gms_token                 = $::gms_token,
  $gms_server_url            = 'https://api.github.com',
  $gms_project_name          = 'abrader/r10k',
  $control_repo              = 'git@github.com:puppetlabs/control-repo.git',
  $code_manager_pub_key_path = '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa',
  $code_manager_pub_key      = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC9aR2y/RfJYNuaWpdnBOSBt3b+hZrIIAW3uEQHA9N/C1Igs8RgGBy/Ngf6lR8k7W1IJBCYhmr8k11eNBDz5fWHulrVP/JWzCauq64o80yp2ORBZLB7liRpIIainN80seYq63MXZFSM2eNtcrVrLsbQfi1Ns0NB23cery+dDVpTDgJILky7ov0QiV8JsDXNkkRxlEjEypT9dx5FEJu2lrEA9S/sGEUuxoqwpib/0ljiv6TodxjSN7SZwKloEh5K5cgmRHymPod6rCzJqDdR7xWdbjGpJM1PsVDxxvYmuNc0r8kUgB9wntA4zx6NUTMhGi+04+GsARF9H+5eg1UHFELz root@master.puppetlabs.vm',
) {
  $target_dir      = "/opt/staging/${module_name}"
  $pe_tarball_path = "${target_dir}/puppet-enterprise-${pe_version}-el-7-x86_64"
  $pe_tarball      = "${cwd}/puppet-enterprise-${pe_version}-el-7-x86_64.tar.gz"
  $staging_file    = "puppet-enterprise-${pe_version}-el-7-x86_64.tar.gz"
  $answers_file    = "${target_dir}/geodss_answers_file"

  host { "Add record for ${::fqdn}":
    name    => $::fqdn,
    ensure  => present,
    ip      => $::ipaddress,
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

  # if $is_spde_dev {
  # }

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
  }

  service { 'firewalld':
    ensure  => stopped,
    enable  => false,
    require => Exec['Installing Puppet Enterprise'],
  }

  # Create directory for Puppet to store public key for Code Manager use
  $code_manager_pub_dirs = ['/etc/puppetlabs/puppetserver', '/etc/puppetlabs/puppetserver/ssh']

  file { $code_manager_pub_dirs:
    ensure => directory,
    owner  => 'pe-puppet',
    group  => 'pe-puppet',
    mode   => '0750',
  }

  file { 'Setup private key for pe-puppet user and Code Manager':
    ensure => file,
    path   => $code_manager_pub_key_path,
    owner  => 'pe-puppet',
    group  => 'pe-puppet',
    mode   => '0400',
    content => $code_manager_pub_key,
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

  node_group { 'PE Master':
    ensure      => present,
    classes     => {
      'pe_repo' => {},
      'pe_repo::platform::el_7_x86_64' => {},
      'puppet_enterprise::profile::master' =>
      {
        'code_manager_auto_configure' => 'true',
        'file_sync_enabled'           => 'true',
        'r10k_private_key'            => $code_manager_pub_key_path,
        'r10k_remote'                 => $control_repo
      },
      'puppet_enterprise::master::code_manager' =>
      {
        'authenticate_webhook' => false
      },
      'puppet_enterprise::profile::master::mcollective'  => {},
      'puppet_enterprise::profile::mcollective::peadmin' => {}
    },
    environment => 'production',
    parent      => 'PE Infrastructure',
  }

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

  git_webhook {'Code Manager Webhook':
    ensure       => present,
    token        => $gms_token,
    project_name => $gms_project_name,
    server_url   => $gms_server_url,
    webhook_url  => "https://${fqdn}:8170/code-manager/v1/webhook?type=github",
  }

}
