#-----outputs.tf-----
#====================
output "Jenkins-Master-Public-URL" {
  value = "http://${module.compute.master_ip}:8080"
}

output "Jenkins-Node-Java-Public-IP" {
  value = module.compute.java_node_ip
}

output "Jenkins-Node-Python-Public-IP" {
  value = module.compute.python_node_ip
}

output "Add-Jenkins-Java-Node-Private-IP-To-Master-KnownHosts" {
  value = "ssh-keyscan -H ${module.compute.java_node_private_ip} >>/var/lib/jenkins/.ssh/known_hosts"
}

output "Add-Jenkins-Python-Node-Private-IP-To-Master-KnownHosts" {
  value = "ssh-keyscan -H ${module.compute.python_node_private_ip} >>/var/lib/jenkins/.ssh/known_hosts"
}  