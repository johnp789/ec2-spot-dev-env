[bastions]
%{ for ip in bastions ~}
${ip}
%{ endfor ~}

[bastions:vars]
ansible_user = ec2-user

[dev_instances]
%{ for ip in dev_instances ~}
${ip}
%{ endfor ~}

[dev_instances:vars]
ansible_ssh_common_args = '-o ProxyCommand="ssh -i \"${ssh_pub_key}\" -o StrictHostKeyChecking=no -W %h:%p -q ec2-user@${first_bastion}"'
ansible_user = arch
