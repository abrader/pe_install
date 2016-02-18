class pe_install::hocon {
  pe_hocon_setting { 'code-manager.authenticate-webhook':
    path    => '/etc/puppetlabs/puppetserver/conf.d/code-manager.conf',
    setting => 'code-manager.authenticate-webhook',
    value   => false,
  }

  service { 'pe-puppetserver':
    ensure    => running,
    enable    => true,
    subscribe => Pe_Hocon_Setting['code-manager.authenticate-webhook'],
  }

}
