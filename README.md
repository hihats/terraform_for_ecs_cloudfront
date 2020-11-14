## Terraform usage

### Initialize
```
$ cd terraform
$ terraform init (-reconfigure)
```

### Select workspace
```
$ terraform workspace new (staging or production)
```

### Adding variables
In case of Ruby on Rails app
```
variable "rails_master_key" {
  default = "**********"
}

variable "developers" {
  default = ["hihats"]
}

In case of deployment by Github Actions
variable "github_action_iam_user" {
  default = "github"
}
```

### Dry run before terraform apply
```
$ terraform plan

~~~

Plan: 30 to add, 0 to change, 0 to destroy.
```

### Apply
```
$ terraform apply
```

### Dependencies of stacks
How each .tf files depends on others
 各 .tfファイルがどのような依存関係にあるか
![terraform_dependencies](https://user-images.githubusercontent.com/2120249/98707614-92989480-23c3-11eb-9ef0-89b90c20fefe.jpg)
