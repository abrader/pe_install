class pe_install (
  $is_spde_dev = $::is_spde_dev,
  $pe_version  = $::pe_version,
  $cwd         = $::cwd,
) {
  $target_dir      = "/opt/staging/${module_name}"
  $pe_tarball_path = "${target_dir}/puppet-enterprise-${pe_version}-el-7-x86_64"
  $pe_tarball      = "${cwd}/puppet-enterprise-${pe_version}-el-7-x86_64.tar.gz"
  $staging_file    = "puppet-enterprise-${pe_version}-el-7-x86_64.tar.gz"
  $answers_file    = "${target_dir}/geodss_answers_file"

# -- File resources below this code will be applied to all files as default

  host { "Add record for ${::fqdn}":
    name    => $::fqdn,
    ensure  => present,
    ip      => $::ipaddress,
    comment => 'SLEP-II Puppet Master - Dev',
  }

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

  #  staging::deploy { 'Install Puppet node manager gem dependency' :
  #    source => 'puppet:///modules/pe_install/puppetclassify.tar.gz',
  #    target => '/opt/puppetlabs/puppet/lib/ruby/gems/2.1.0/puppetclassify-0.1.3',
  #  }

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

  node_group { 'Production environment':
    ensure               => present,
    environment          => 'production',
    override_environment => true,
    parent               => 'All Nodes',
    rule                 => ['and', ['=', ['fact', 'name'], $::fqdn]],
  }  

  node_group { 'Agent-specified environment':
    ensure               => present,
    environment          => 'agent-specified',
    override_environment => true,
    parent               => 'Production environment',
    rule                 => ['and', ['~', ['fact', 'name'], '.*']],
  }

}

