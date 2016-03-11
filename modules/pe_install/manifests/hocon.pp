class pe_install::hocon (
  $control_repo          = 'git@140.188.246.24:SLEP-II/control.git',
  $code_manager_key_path = '/etc/puppetlabs/puppetserver/ssh',
) {
  $code_manager_private_key_path = "${code_manager_key_path}/id-control_repo.rsa"
  
  pe_hocon_setting { 'code-manager.authenticate-webhook':
    path    => '/etc/puppetlabs/puppetserver/conf.d/code-manager.conf',
    setting => 'code-manager.authenticate-webhook',
    value   => false,
  }

  service { 'pe-puppetserver':
    ensure    => running,
    enable    => true,
    subscribe => Pe_Hocon_Setting['code-manager.authenticate-webhook'],
    before    => Node_Group['PE Master'],
  }

  node_group { 'PE Master':
    ensure                                 => present,
    classes                                => {
      'pe_repo'                            => {},
      'pe_repo::platform::el_7_x86_64'     => {},
      'pe_install::hocon'                  => {},
      'puppet_enterprise::profile::master' =>
      {
        'code_manager_auto_configure' => true,
        'file_sync_enabled'           => true,
        'r10k_private_key'            => $code_manager_private_key_path,
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
}
