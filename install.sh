#!/usr/bin/env bash

/bin/rpm -Uvh puppet-agent-1.3.2-1.el7.x86_64.rpm
FACTER_pe_version=2015.3.1 FACTER_cwd=/usr/local/puppet /opt/puppetlabs/bin/puppet apply modules/pe_install/examples/init.pp --modulepath=modules

