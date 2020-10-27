# Quick dev environment

To start up this dev environment:

```
# check and modify terraform/variables.tf as desired
cd terraform
terraform init
terraform apply
cd ../ansible
ansible-playbook -i hosts.cfg dev.yml
```
